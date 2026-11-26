/*
 * Arduino core functions used:
 *   millis()
 *   pinMode()
 *   digitalRead()
 */

#include <Arduino.h>
#include "psu_board.h"
#include "psu_power_switch.h"

#define POWER_SWITCH_DEBOUNCE_MS  20UL   /* level must stay this long, longer than the switch bounce */

/* power switch debounce state */
static bool     g_switch_on        = false;  /* debounced level, true = ON */
static bool     g_switch_raw_prev  = false;  /* pin level on the last update */
static uint32_t g_switch_change_ms = 0;      /* time the pin level last changed */

/**
 * @brief Set up the power switch pin, the switch counts as OFF until it is read.
 */
void psu_power_switch_init(void)
{
    /* pull-down keeps an unconnected pin at OFF */
    pinMode((uint8_t)POWER_SWITCH_PIN, (uint8_t)INPUT_PULLDOWN);

    g_switch_on        = false;
    g_switch_raw_prev  = false;
    g_switch_change_ms = millis();
}

/**
 * @brief Read the power switch, a new level is accepted only after it stays for POWER_SWITCH_DEBOUNCE_MS.
 * @return true while the debounced switch is ON.
 */
bool psu_power_switch_update(void)
{
    uint32_t now_ms = millis();
    bool     raw    = (digitalRead((uint8_t)POWER_SWITCH_PIN) == HIGH);

    /* any change restarts the wait, so bounce never gets through */
    if (raw != g_switch_raw_prev) {
        g_switch_raw_prev  = raw;
        g_switch_change_ms = now_ms;
    }

    /* wrap-safe elapsed time */
    if ((uint32_t)(now_ms - g_switch_change_ms) >= POWER_SWITCH_DEBOUNCE_MS) {
        g_switch_on = raw;
    }

    return g_switch_on;
}
