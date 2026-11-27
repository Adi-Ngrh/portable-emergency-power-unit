#include "psu_fsm.h"

/**
 * @brief Reset the FSM at power-on, same as fsm.sv reset.
 * @param fsm FSM instance.
 */
void psu_fsm_init(psu_fsm_t *fsm)
{
    fsm->state               = FSM_STATE_OFF;
    fsm->booted_once         = false;
    fsm->battery_fault_latch = false;

    fsm->out.system_enable    = false;
    fsm->out.boot_success     = false;
    fsm->out.shutdown_success = true;
}

/**
 * @brief Run one FSM update: evaluate state, apply overrides, commit.
 * @param fsm FSM instance.
 * @param in  FSM inputs.
 */
void psu_fsm_update(psu_fsm_t *fsm, const psu_fsm_inputs_t *in)
{
    /* state enum from psu_fsm.h */
    psu_fsm_state_t   next_state = fsm->state;
    /* FSM outputs struct from psu_fsm.h */
    psu_fsm_outputs_t next_out;

    bool fpga_lost;
    bool shutdown_trigger;
    bool warning_trigger;
    bool critical_trigger;

    /* triggers, fpga_lost is MCU only: a frozen safety monitor ends in a graceful shutdown */
    fpga_lost        = !in->fpga_alive;
    shutdown_trigger = in->manual_shutdown || in->shutdown_request || in->battery_critical || fpga_lost;
    warning_trigger  = in->warning_request || in->battery_low;
    critical_trigger = in->critical_request;

    /* default outputs */
    next_out.system_enable    = false;
    next_out.boot_success     = false;
    next_out.shutdown_success = false;

    switch (fsm->state) {

    /* OFF: after power-on BOOT once when the FPGA is alive, then final until the power switch is cycled */
    case FSM_STATE_OFF:
        next_out.shutdown_success = true;
        if (!fsm->booted_once && in->fpga_alive) {
            fsm->booted_once = true;
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
        if (!warning_trigger) {
            next_state = FSM_STATE_NORMAL;
        }
        break;

    /* CRITICAL: all outputs off, final until the power switch is turned off and on again */
    case FSM_STATE_CRITICAL:
        break;

    /* SHUTDOWN: wait for main system shutdown */
    case FSM_STATE_SHUTDOWN:
        next_out.system_enable = true;
        if (in->shutdown_done) {
            next_out.system_enable    = false;
            next_out.shutdown_success = true;
            if (fsm->battery_fault_latch) {
                next_state = FSM_STATE_RECOVERY;
            }
            else {
                next_state = FSM_STATE_OFF;
            }
        }
        break;

    /* RECOVERY: reboot when battery_critical clears and the FPGA is alive */
    case FSM_STATE_RECOVERY:
        next_out.shutdown_success = true;
        if (!in->battery_critical && in->fpga_alive) {
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

    fsm->state = next_state;
    fsm->out   = next_out;
}
