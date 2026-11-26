/*
 * Arduino core functions used:
 *   pinMode()
 *   digitalWrite()
 */

#include <Arduino.h>
#include "psu_board.h"
#include "psu_mcu_status.h"

/**
 * @brief Set up the main system status pins to the FPGA, both start low.
 */
void psu_mcu_status_init(void)
{
    pinMode((uint8_t)BOOT_SUCCESS_PIN, (uint8_t)OUTPUT);
    digitalWrite((uint8_t)BOOT_SUCCESS_PIN, (uint8_t)LOW);

    pinMode((uint8_t)SHUTDOWN_SUCCESS_PIN, (uint8_t)OUTPUT);
    digitalWrite((uint8_t)SHUTDOWN_SUCCESS_PIN, (uint8_t)LOW);
}

/**
 * @brief Drive the main system status pins to the FPGA.
 * @param boot_success     FSM output, high while the main system is up.
 * @param shutdown_success FSM output, high while the main system is off.
 */
void psu_mcu_status_update(bool boot_success, bool shutdown_success)
{
    if (boot_success) {
        digitalWrite((uint8_t)BOOT_SUCCESS_PIN, (uint8_t)HIGH);
    }
    else {
        digitalWrite((uint8_t)BOOT_SUCCESS_PIN, (uint8_t)LOW);
    }

    if (shutdown_success) {
        digitalWrite((uint8_t)SHUTDOWN_SUCCESS_PIN, (uint8_t)HIGH);
    }
    else {
        digitalWrite((uint8_t)SHUTDOWN_SUCCESS_PIN, (uint8_t)LOW);
    }
}
