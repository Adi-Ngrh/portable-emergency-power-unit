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
static uint8_t  g_temp_addr[DS18B20_COUNT][DS18B20_ADDR_BYTES];
static bool     g_temp_converting = false;
static uint32_t g_temp_request_ms = 0;

/**
 * @brief Find all DS18B20 and set 12-bit, non-blocking conversions.
 * @return true if every sensor is found.
 */
bool psu_temperature_sensor_init(void)
{
    bool ok = true;
    int  i;

    /* all sensors must be found */
    g_temp_sensor.begin();
    if (g_temp_sensor.getDeviceCount() != DS18B20_COUNT) {
        ok = false;
    }
    for (i = 0; i < DS18B20_COUNT; i++) {
        if (!g_temp_sensor.getAddress(g_temp_addr[i], (uint8_t)i)) {
            ok = false;
        }
    }

    /* 12-bit, non-blocking conversions */
    g_temp_sensor.setResolution((uint8_t)DS18B20_RESOLUTION_BITS);
    g_temp_sensor.setWaitForConversion(false);
    g_temp_converting = false;

    return ok;
}

/**
 * @brief Non-blocking read of all DS18B20, reports the hottest one.
 * @param[out] reading Temperature reading, updated when a conversion finishes.
 */
void psu_temperature_read(psu_temperature_reading_t *reading)
{
    uint32_t now_ms   = millis();
    int16_t  hottest  = INT16_MIN;
    bool     any_good = false;
    bool     any_bad  = false;
    int32_t  raw;
    int16_t  value;
    int      i;

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

    for (i = 0; i < DS18B20_COUNT; i++) {
        raw = g_temp_sensor.getTemp(g_temp_addr[i]);

        /* disconnected, CRC error, or power-on value (85 degC still ends in shutdown) */
        if (raw == DEVICE_DISCONNECTED_RAW || raw == DS18B20_POWER_ON_RAW) {
            any_bad = true;
        }
        else {
            any_good = true;
            value    = (int16_t)(raw / 8);   /* 1/128 degC to 1/16 degC */
            if (value > hottest) {
                hottest = value;
            }
        }
    }

    reading->error = any_bad;
    if (any_good) {
        reading->temperature = hottest;
        reading->valid       = true;
    }
}
