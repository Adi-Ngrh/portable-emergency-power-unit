/*
 * Arduino core functions used:
 *   millis()
 */

#include <Arduino.h>
#include "psu_fsm.h"

#define FSM_MAX_RETRY                 3U     /* max retries out of CRITICAL */
#define FSM_HEARTBEAT_HALF_PERIOD_MS  250UL  /* must stay well under FPGA 3 s watchdog */

/**
 * @brief Reset the FSM, same as fsm.sv reset.
 * @param fsm FSM instance.
 */
void psu_fsm_init(psu_fsm_t *fsm)
{
    fsm->state               = FSM_STATE_OFF;
    fsm->heartbeat_ms        = millis();
    fsm->manual_power_prev   = false;
    fsm->battery_fault_latch = false;
    fsm->retry_count         = 0;

    fsm->out.system_enable    = false;
    fsm->out.warning_led      = false;
    fsm->out.critical_clear   = false;
    fsm->out.buzzer_alert     = false;
    fsm->out.recovery_mode    = false;
    fsm->out.boot_success     = false;
    fsm->out.shutdown_success = true;
    fsm->out.mcu_heartbeat    = false;
}

/**
 * @brief Run one FSM update: evaluate state, apply overrides, commit.
 * @param fsm FSM instance.
 * @param in  FSM inputs.
 */
void psu_fsm_update(psu_fsm_t *fsm, const psu_fsm_inputs_t *in)
{
    uint32_t          now_ms     = millis();
    /* state enum from psu_fsm.h */
    psu_fsm_state_t   next_state = fsm->state;
    /* FSM outputs struct from psu_fsm.h */
    psu_fsm_outputs_t next_out;

    bool manual_power_pressed;
    bool shutdown_trigger;
    bool warning_trigger;
    bool critical_trigger;
    bool critical_retry_allowed;

    /* triggers */
    manual_power_pressed   = in->manual_power && !fsm->manual_power_prev;
    shutdown_trigger       = in->manual_shutdown || in->shutdown_request || in->battery_critical;
    warning_trigger        = in->warning_request || in->battery_low;
    critical_trigger       = in->critical_request;
    critical_retry_allowed = manual_power_pressed && (fsm->retry_count < FSM_MAX_RETRY);

    /* default outputs */
    next_out.system_enable    = false;
    next_out.warning_led      = false;
    next_out.critical_clear   = false;
    next_out.buzzer_alert     = false;
    next_out.recovery_mode    = false;
    next_out.boot_success     = false;
    next_out.shutdown_success = false;
    next_out.mcu_heartbeat    = fsm->out.mcu_heartbeat;

    /* heartbeat stops if updates stop */
    if ((uint32_t)(now_ms - fsm->heartbeat_ms) >= FSM_HEARTBEAT_HALF_PERIOD_MS) {
        fsm->heartbeat_ms      = now_ms;
        next_out.mcu_heartbeat = !fsm->out.mcu_heartbeat;
    }

    switch (fsm->state) {

    /* OFF: wait for power button */
    case FSM_STATE_OFF:
        next_out.shutdown_success = true;
        if (manual_power_pressed) {
            next_state = FSM_STATE_BOOT;
        }
        break;

    /* BOOT: wait for main system init result */
    case FSM_STATE_BOOT:
        next_out.system_enable = true;
        if (in->boot_passed) {
            next_out.boot_success = true;
            next_state = FSM_STATE_NORMAL;
        }
        else if (in->boot_failed) {
            next_out.system_enable    = false;
            next_out.shutdown_success = true;
            next_state = FSM_STATE_OFF;
        }
        break;

    /* NORMAL: leaves only via overrides */
    case FSM_STATE_NORMAL:
        next_out.system_enable = true;
        next_out.boot_success  = true;
        break;

    /* WARNING: back to NORMAL when warnings clear */
    case FSM_STATE_WARNING:
        next_out.system_enable = true;
        next_out.boot_success  = true;
        next_out.warning_led   = true;
        if (!warning_trigger) {
            next_state = FSM_STATE_NORMAL;
        }
        break;

    /* CRITICAL: system off, retry via power button */
    case FSM_STATE_CRITICAL:
        next_out.warning_led  = true;
        next_out.buzzer_alert = true;
        if (critical_retry_allowed) {
            next_out.critical_clear = true;
            next_state = FSM_STATE_BOOT;
        }
        break;

    /* SHUTDOWN: wait for main system shutdown */
    case FSM_STATE_SHUTDOWN:
        next_out.system_enable = true;
        if (in->shutdown_done) {
            next_out.system_enable    = false;
            next_out.shutdown_success = true;
            next_state = fsm->battery_fault_latch ? FSM_STATE_RECOVERY : FSM_STATE_OFF;
        }
        break;

    /* RECOVERY: reboot when battery_critical clears */
    case FSM_STATE_RECOVERY:
        next_out.recovery_mode    = true;
        next_out.shutdown_success = true;
        if (!in->battery_critical) {
            next_state = FSM_STATE_BOOT;
        }
        break;

    default:
        next_state = FSM_STATE_OFF;
        break;
    }

    /* global overrides, highest priority first */
    if (critical_trigger &&
        (fsm->state == FSM_STATE_NORMAL  || fsm->state == FSM_STATE_WARNING ||
         fsm->state == FSM_STATE_BOOT    || fsm->state == FSM_STATE_SHUTDOWN)) {
        next_state = FSM_STATE_CRITICAL;
    }
    else if (shutdown_trigger &&
             (fsm->state == FSM_STATE_NORMAL || fsm->state == FSM_STATE_WARNING)) {
        next_state = FSM_STATE_SHUTDOWN;
    }
    else if (warning_trigger && fsm->state == FSM_STATE_NORMAL) {
        next_state = FSM_STATE_WARNING;
    }

    /* battery fault latch */
    if (in->battery_critical) {
        fsm->battery_fault_latch = true;
    }
    else if (next_state == FSM_STATE_NORMAL) {
        fsm->battery_fault_latch = false;
    }

    /* count retries out of CRITICAL */
    if (fsm->state == FSM_STATE_CRITICAL && next_state == FSM_STATE_BOOT) {
        fsm->retry_count++;
    }

    fsm->state             = next_state;
    fsm->out               = next_out;
    fsm->manual_power_prev = in->manual_power;
}
