/*
 * Arduino core functions used:
 *   pinMode()
 *   digitalWrite()
 */

#include <Arduino.h>
#include "psu_board.h"
#include "psu_mcu_heartbeat.h"

/**
 * @brief Set up the heartbeat pin to the FPGA, starts low.
 */
void psu_mcu_heartbeat_init(void)
{
    pinMode((uint8_t)MCU_HEARTBEAT_PIN, (uint8_t)OUTPUT);
    digitalWrite((uint8_t)MCU_HEARTBEAT_PIN, (uint8_t)LOW);
}

/**
 * @brief Drive the heartbeat pin to the FPGA.
 * @param level Heartbeat level from the FSM, toggles every 250 ms.
 */
void psu_mcu_heartbeat_update(bool level)
{
    if (level) {
        digitalWrite((uint8_t)MCU_HEARTBEAT_PIN, (uint8_t)HIGH);
    }
    else {
        digitalWrite((uint8_t)MCU_HEARTBEAT_PIN, (uint8_t)LOW);
    }
}
