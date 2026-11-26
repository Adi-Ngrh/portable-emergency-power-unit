/*
 * Arduino core functions used:
 *   millis()
 *   pinMode()
 *   digitalRead()
 */

#include <Arduino.h>
#include "psu_board.h"
#include "psu_fpga_heartbeat.h"

#define FPGA_HEARTBEAT_TIMEOUT_MS  3000UL   /* same timeout the FPGA uses for the MCU heartbeat */

/* FPGA heartbeat watch state */
static bool     g_fpga_level_prev  = false;  /* pin level on the last update */
static bool     g_fpga_toggle_seen = false;  /* at least one toggle since start */
static uint32_t g_fpga_toggle_ms   = 0;      /* time of the last toggle */

/**
 * @brief Set up the heartbeat pin from the FPGA, no toggle seen yet.
 */
void psu_fpga_heartbeat_init(void)
{
    pinMode((uint8_t)FPGA_HEARTBEAT_PIN, (uint8_t)INPUT);

    g_fpga_level_prev  = (digitalRead((uint8_t)FPGA_HEARTBEAT_PIN) == HIGH);
    g_fpga_toggle_seen = false;
    g_fpga_toggle_ms   = millis();
}

/**
 * @brief Watch the heartbeat pin from the FPGA, any toggle counts as alive.
 * @return true if the FPGA toggled its heartbeat within FPGA_HEARTBEAT_TIMEOUT_MS.
 */
bool psu_fpga_heartbeat_update(void)
{
    uint32_t now_ms = millis();
    bool     level  = (digitalRead((uint8_t)FPGA_HEARTBEAT_PIN) == HIGH);

    /* a toggle restarts the timeout */
    if (level != g_fpga_level_prev) {
        g_fpga_toggle_seen = true;
        g_fpga_toggle_ms   = now_ms;
    }
    g_fpga_level_prev = level;

    /* no toggle since start: not proven alive yet */
    if (!g_fpga_toggle_seen) {
        return false;
    }

    /* wrap-safe elapsed time */
    if ((uint32_t)(now_ms - g_fpga_toggle_ms) >= FPGA_HEARTBEAT_TIMEOUT_MS) {
        return false;
    }

    return true;
}
