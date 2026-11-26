/*
 * Arduino core functions used:
 *   millis()
 */

#include <Arduino.h>
#include <stdint.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include "psu_board.h"
#include "psu_temperature_sensor.h"

/* DS18B20 settings */
#define DS18B20_ADDR_BYTES       8              /* ROM address length */
#define DS18B20_RESOLUTION_BITS  12             /* 0.0625 degC per bit */
#define DS18B20_CONVERSION_MS    750UL          /* tCONV max at 12-bit */
#define DS18B20_POWER_ON_RAW     (85L * 128L)   /* 85 degC power-on value, library raw units */

/* 1-Wire bus object from OneWire.h */
static OneWire g_one_wire((uint8_t)DS18B20_PIN);

/* DS18B20 driver object from DallasTemperature.h */
static DallasTemperature g_temp_sensor(&g_one_wire);

/* DS18B20 state */
static uint8_t  g_temp_addr[DS18B20_ADDR_BYTES];   /* ROM address of the sensor */
static bool     g_temp_converting = false;
static uint32_t g_temp_request_ms = 0;

/**
 * @brief Find the DS18B20 and set 12-bit, non-blocking conversions.
 * @return true if exactly one sensor is found.
 */
bool psu_temperature_sensor_init(void)
{
    bool ok = true;

    /* exactly one sensor on the bus */
    g_temp_sensor.begin();
    if (g_temp_sensor.getDeviceCount() != 1) {
        ok = false;
    }
    if (!g_temp_sensor.getAddress(g_temp_addr, (uint8_t)0)) {
        ok = false;
    }

    /* 12-bit, non-blocking conversions */
    g_temp_sensor.setResolution((uint8_t)DS18B20_RESOLUTION_BITS);
    g_temp_sensor.setWaitForConversion(false);
    g_temp_converting = false;

    return ok;
}

/**
 * @brief Non-blocking read of the DS18B20.
 * @param[out] reading Temperature reading, updated when a conversion finishes.
 */
void psu_temperature_read(psu_temperature_reading_t *reading)
{
    uint32_t now_ms = millis();
    int32_t  raw;

    reading->valid = false;

    /* start a conversion */
    if (!g_temp_converting) {
        g_temp_sensor.requestTemperatures();
        g_temp_request_ms = now_ms;
        g_temp_converting = true;
        return;
    }

    /* wait until the conversion is done */
    if ((uint32_t)(now_ms - g_temp_request_ms) < DS18B20_CONVERSION_MS) {
        return;
    }
    g_temp_converting = false;

    raw = g_temp_sensor.getTemp(g_temp_addr);

    /* disconnected, CRC error, or power-on value (85 degC still ends in shutdown) */
    if (raw == DEVICE_DISCONNECTED_RAW || raw == DS18B20_POWER_ON_RAW) {
        reading->error = true;
        return;
    }

    reading->temperature = (int16_t)(raw / 8);   /* 1/128 degC to 1/16 degC */
    reading->valid       = true;
    reading->error       = false;
}
