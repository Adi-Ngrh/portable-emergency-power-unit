/*
 * Arduino core functions used:
 *   millis()
 */

#include <Arduino.h>
#include <stdint.h>
#include <stddef.h>
#include <Wire.h>
#include "psu_board.h"
#include "psu_power_sensor.h"

/* INA226 registers */
#define INA226_REG_CONFIG     0x00
#define INA226_REG_BUS        0x02
#define INA226_REG_POWER      0x03
#define INA226_REG_CURRENT    0x04
#define INA226_REG_CAL        0x05

/* INA226 settings */
#define INA226_CONFIG_VALUE   0x4527   /* 16 avg, 1.1 ms conversion, continuous shunt+bus */
#define INA226_CAL_VALUE      5120U    /* 0.00512 / (1 mA LSB * 1 mOhm external shunt) */
#define INA226_BUS_LSB_UV     1250L    /* 1.25 mV/bit */
#define INA226_CURRENT_LSB_UA 1000L    /* 1 mA/bit */
#define INA226_POWER_LSB_UW   25000L   /* 25 x current LSB */

/* read once per conversion cycle: 16 x (1.1 + 1.1) ms = 35.2 ms */
#define POWER_SENSOR_READ_INTERVAL_MS  36UL

/* time of the last read */
static uint32_t g_power_last_ms = 0;

/**
 * @brief Write one 16-bit INA226 register.
 * @param reg   Register address.
 * @param value Value to write.
 * @return true if the INA226 acknowledged.
 */
static bool ina226_write(uint8_t reg, uint16_t value)
{
    Wire.beginTransmission((uint8_t)INA226_ADDR);
    Wire.write(reg);
    Wire.write((uint8_t)(value >> 8));
    Wire.write((uint8_t)(value & 0xFF));
    return Wire.endTransmission() == 0;
}

/**
 * @brief Read one 16-bit INA226 register.
 * @param reg        Register address.
 * @param[out] value Value read.
 * @return true if the read succeeded.
 */
static bool ina226_read(uint8_t reg, uint16_t *value)
{
    uint8_t msb;
    uint8_t lsb;

    Wire.beginTransmission((uint8_t)INA226_ADDR);
    Wire.write(reg);
    if (Wire.endTransmission(false) != 0) {
        return false;
    }
    if (Wire.requestFrom((uint8_t)INA226_ADDR, (size_t)2, true) != 2) {
        return false;
    }

    /* two statements, so the byte order is guaranteed */
    msb    = (uint8_t)Wire.read();
    lsb    = (uint8_t)Wire.read();
    *value = (uint16_t)((msb << 8) | lsb);
    return true;
}

/**
 * @brief Start the I2C bus, configure and calibrate the INA226.
 * @return true if the INA226 responds and keeps its configuration.
 */
bool psu_power_sensor_init(void)
{
    bool     ok = true;
    uint16_t readback;

    /* I2C bus, other I2C drivers may call this again safely */
    Wire.begin(SDA_PIN, SCL_PIN, (uint32_t)I2C_CLOCK_HZ);

    if (!ina226_write((uint8_t)INA226_REG_CONFIG, (uint16_t)INA226_CONFIG_VALUE)) {
        ok = false;
    }
    if (!ina226_write((uint8_t)INA226_REG_CAL, (uint16_t)INA226_CAL_VALUE)) {
        ok = false;
    }

    /* read config back to verify */
    if (!ina226_read((uint8_t)INA226_REG_CONFIG, &readback) || readback != INA226_CONFIG_VALUE) {
        ok = false;
    }

    /* first read waits one conversion cycle */
    g_power_last_ms = millis();

    return ok;
}

/**
 * @brief Read voltage, current and power once per conversion cycle.
 * @param[out] reading Power reading, updated when a new read is done.
 */
void psu_power_read(psu_power_reading_t *reading)
{
    uint32_t now_ms = millis();
    uint16_t raw_bus;
    uint16_t raw_current;
    uint16_t raw_power;

    reading->valid = false;

    /* wait for the next conversion cycle */
    if ((uint32_t)(now_ms - g_power_last_ms) < POWER_SENSOR_READ_INTERVAL_MS) {
        return;
    }
    g_power_last_ms = now_ms;

    if (!ina226_read((uint8_t)INA226_REG_BUS, &raw_bus) ||
        !ina226_read((uint8_t)INA226_REG_CURRENT, &raw_current) ||
        !ina226_read((uint8_t)INA226_REG_POWER, &raw_power)) {
        reading->error = true;
        return;
    }

    /* raw to mV, mA, mW (current register is signed) */
    reading->voltage_mv = (int32_t)raw_bus * INA226_BUS_LSB_UV / 1000L;
    reading->current_ma = (int32_t)(int16_t)raw_current * INA226_CURRENT_LSB_UA / 1000L;
    reading->power_mw   = (int32_t)raw_power * INA226_POWER_LSB_UW / 1000L;
    reading->valid      = true;
    reading->error      = false;
}
