/*
 * Arduino core functions used:
 *   pinMode()
 *   digitalWrite()
 */

#include <Arduino.h>
#include "psu_board.h"
#include "psu_power_sensor.h"
#include "psu_temperature_sensor.h"

/**
 * @brief Initialize the main system board (sensors only for now).
 * @return true if every sensor responds.
 */
bool psu_board_init(void)
{
    bool ok = true;

    /* power sensor (also starts the I2C bus) */
    if (!psu_power_sensor_init()) {
        ok = false;
    }

    /* temperature sensor, skipped until it is soldered */
    if (DS18B20_INSTALLED) {
        if (!psu_temperature_sensor_init()) {
            ok = false;
        }
    }

    return ok;
}

/**
 * @brief Set up the main relay pin, relay open (main system off) from the start.
 */
void psu_main_relay_init(void)
{
    pinMode((uint8_t)MAIN_RELAY_PIN, (uint8_t)OUTPUT);
    digitalWrite((uint8_t)MAIN_RELAY_PIN, (uint8_t)MAIN_RELAY_OPEN_LEVEL);
}

/**
 * @brief Close or open the main relay that powers the inverter, charging module and load.
 * @param closed FSM output system_enable, true closes the relay (main system on).
 */
void psu_main_relay_update(bool closed)
{
    if (closed) {
        digitalWrite((uint8_t)MAIN_RELAY_PIN, (uint8_t)MAIN_RELAY_CLOSED_LEVEL);
    }
    else {
        digitalWrite((uint8_t)MAIN_RELAY_PIN, (uint8_t)MAIN_RELAY_OPEN_LEVEL);
    }
}
