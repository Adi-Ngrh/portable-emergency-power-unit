/*
 * Arduino core functions used:
 *   millis()
 *   pinMode()
 *   digitalRead()
 */

#include <Arduino.h>
#include "psu_board.h"
#include "psu_fpga_fault.h"

#define FPGA_FAULT_STABLE_MS  20UL   /* code must stay this long, so a half-changed code is never taken */

/* FPGA fault code read state */
static uint8_t  g_fpga_code_stable    = 0;   /* accepted code */
static uint8_t  g_fpga_code_raw_prev  = 0;   /* code on the last update */
static uint32_t g_fpga_code_change_ms = 0;   /* time the code last changed */

/**
 * @brief Read the 3 fault code pins once.
 * @return Code 0 to 7, same numbering as fault_code_bus in fee.sv.
 */
static uint8_t fpga_fault_read_pins(void)
{
    uint8_t code = 0;

    if (digitalRead((uint8_t)FPGA_FAULT_BIT0_PIN) == HIGH) {
        code = (uint8_t)(code + 1U);
    }
    if (digitalRead((uint8_t)FPGA_FAULT_BIT1_PIN) == HIGH) {
        code = (uint8_t)(code + 2U);
    }
    if (digitalRead((uint8_t)FPGA_FAULT_BIT2_PIN) == HIGH) {
        code = (uint8_t)(code + 4U);
    }

    return code;
}

/**
 * @brief Set up the fault code pins from the FPGA, the code counts as "no fault" until read.
 */
void psu_fpga_fault_init(void)
{
    pinMode((uint8_t)FPGA_FAULT_BIT0_PIN, (uint8_t)INPUT);
    pinMode((uint8_t)FPGA_FAULT_BIT1_PIN, (uint8_t)INPUT);
    pinMode((uint8_t)FPGA_FAULT_BIT2_PIN, (uint8_t)INPUT);

    g_fpga_code_stable    = 0;
    g_fpga_code_raw_prev  = 0;
    g_fpga_code_change_ms = millis();
}

/**
 * @brief Read the FPGA fault code, a new code is accepted only after it stays for FPGA_FAULT_STABLE_MS.
 * @return Highest active FPGA fault, only meaningful while the FPGA heartbeat is alive.
 */
psu_fee_code_t psu_fpga_fault_update(void)
{
    uint32_t now_ms = millis();
    uint8_t  raw    = fpga_fault_read_pins();

    /* any change restarts the wait, the 3 pins never change at exactly the same moment */
    if (raw != g_fpga_code_raw_prev) {
        g_fpga_code_raw_prev  = raw;
        g_fpga_code_change_ms = now_ms;
    }

    /* wrap-safe elapsed time */
    if ((uint32_t)(now_ms - g_fpga_code_change_ms) >= FPGA_FAULT_STABLE_MS) {
        g_fpga_code_stable = raw;
    }

    return (psu_fee_code_t)g_fpga_code_stable;
}
