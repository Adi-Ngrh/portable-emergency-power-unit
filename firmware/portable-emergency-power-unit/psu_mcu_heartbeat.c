/*
 * Arduino core functions used:
 *   millis()
 *   pinMode()
 *   digitalWrite()
 */

#include <Arduino.h>
#include "psu_board.h"
#include "psu_mcu_heartbeat.h"

#define MCU_HEARTBEAT_HALF_PERIOD_MS  250UL   /* time between toggles, well under the FPGA's 3 s timeout */

/* heartbeat state */
static bool     g_heartbeat_level     = false;  /* pin level now */
static uint32_t g_heartbeat_toggle_ms = 0;      /* time of the last toggle */

/**
 * @brief Set up the heartbeat pin to the FPGA, starts low.
 */
void psu_mcu_heartbeat_init(void)
{
    pinMode((uint8_t)MCU_HEARTBEAT_PIN, (uint8_t)OUTPUT);
    digitalWrite((uint8_t)MCU_HEARTBEAT_PIN, (uint8_t)LOW);
    g_heartbeat_level     = false;
    g_heartbeat_toggle_ms = millis();
}

/**
 * @brief Toggle the heartbeat pin every MCU_HEARTBEAT_HALF_PERIOD_MS, in every state.
 *        Called by the control task, so the heartbeat stops if the control task stops.
 */
void psu_mcu_heartbeat_update(void)
{
    uint32_t now_ms = millis();

    /* wrap-safe elapsed time */
    if ((uint32_t)(now_ms - g_heartbeat_toggle_ms) < MCU_HEARTBEAT_HALF_PERIOD_MS) {
        return;
    }
    g_heartbeat_toggle_ms = now_ms;
    g_heartbeat_level     = !g_heartbeat_level;

    if (g_heartbeat_level) {
        digitalWrite((uint8_t)MCU_HEARTBEAT_PIN, (uint8_t)HIGH);
    }
    else {
        digitalWrite((uint8_t)MCU_HEARTBEAT_PIN, (uint8_t)LOW);
    }
}
