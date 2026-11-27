#include <stdio.h>
#include <stddef.h>
#include "psu_event_log.h"

/**
 * @brief Clear the log.
 * @param[out] log Event log.
 */
void psu_event_log_init(psu_event_log_t *log)
{
    log->next            = 0;
    log->count           = 0;
    log->last_state      = FSM_STATE_OFF;
    log->last_fault      = FEE_CODE_DEFAULT;
    log->last_fpga_alive = false;
    log->last_fpga_fault = FEE_CODE_DEFAULT;
}

/**
 * @brief Add one event, the oldest is dropped when full.
 * @param[in,out] log Event log.
 * @param now_ms      Current uptime in ms.
 * @param level       Event class.
 * @param text        Event text, cut to EVENT_LOG_TEXT_LEN - 1 chars.
 */
void psu_event_log_add(psu_event_log_t *log, uint32_t now_ms,
                       psu_event_level_t level, const char *text)
{
    /* event struct from psu_event_log.h */
    psu_event_t *event = &log->entry[log->next];

    event->time_ms = now_ms;
    event->level   = level;
    snprintf(event->text, EVENT_LOG_TEXT_LEN, "%s", text);

    log->next = (uint8_t)((log->next + 1U) % EVENT_LOG_SIZE);
    if (log->count < EVENT_LOG_SIZE) {
        log->count++;
    }
}

/**
 * @brief Log one fault code change: set ("E3 OVERTEMP") or cleared ("E3 OVERTEMP CLEARED").
 * @param[in,out] log Event log.
 * @param now_ms      Current uptime in ms.
 * @param source      Text put in front, "" for the MCU, "FPGA " for the FPGA.
 * @param old_fault   Fault code before the change.
 * @param new_fault   Fault code after the change.
 */
static void event_log_fault_change(psu_event_log_t *log, uint32_t now_ms, const char *source,
                                   psu_fee_code_t old_fault, psu_fee_code_t new_fault)
{
    char text[EVENT_LOG_TEXT_LEN];

    if (new_fault != FEE_CODE_DEFAULT) {
        snprintf(text, sizeof(text), "%sE%u %s",
                 source, (unsigned int)new_fault, psu_event_log_fault_name(new_fault));
        psu_event_log_add(log, now_ms, psu_event_log_fault_level(new_fault), text);
    }
    else {
        snprintf(text, sizeof(text), "%sE%u %s CLEARED",
                 source, (unsigned int)old_fault, psu_event_log_fault_name(old_fault));
        psu_event_log_add(log, now_ms, EVENT_LEVEL_CLEARED, text);
    }
}

/**
 * @brief Log MCU FSM state changes and MCU FEE fault code changes.
 *        Entering CRITICAL or OFF also logs "TURN OFF POWER SWITCH".
 * @param[in,out] log Event log.
 * @param now_ms      Current uptime in ms.
 * @param state       Current FSM state.
 * @param fault       Current FEE fault code (highest active fault only).
 */
void psu_event_log_track(psu_event_log_t *log, uint32_t now_ms,
                         psu_fsm_state_t state, psu_fee_code_t fault)
{
    char text[EVENT_LOG_TEXT_LEN];

    if (fault != log->last_fault) {
        event_log_fault_change(log, now_ms, "", log->last_fault, fault);
        log->last_fault = fault;
    }

    if (state != log->last_state) {
        snprintf(text, sizeof(text), "STATE %s -> %s",
                 psu_event_log_state_name(log->last_state), psu_event_log_state_name(state));
        psu_event_log_add(log, now_ms, EVENT_LEVEL_INFO, text);
        log->last_state = state;

        /* CRITICAL and OFF are final, only the power switch can turn the unit off (charging included) */
        if (state == FSM_STATE_CRITICAL) {
            psu_event_log_add(log, now_ms, EVENT_LEVEL_CRITICAL, "TURN OFF POWER SWITCH");
        }
        else if (state == FSM_STATE_OFF) {
            psu_event_log_add(log, now_ms, EVENT_LEVEL_WARNING, "TURN OFF POWER SWITCH");
        }
    }
}

/**
 * @brief Log FPGA heartbeat changes and FPGA fault code changes.
 * @param[in,out] log Event log.
 * @param now_ms      Current uptime in ms.
 * @param fpga_alive  FPGA heartbeat seen in the last 3 s.
 * @param fpga_fault  FPGA fault code (highest active fault only), ignored while the FPGA is not alive.
 */
void psu_event_log_track_fpga(psu_event_log_t *log, uint32_t now_ms,
                              bool fpga_alive, psu_fee_code_t fpga_fault)
{
    if (fpga_alive != log->last_fpga_alive) {
        if (fpga_alive) {
            psu_event_log_add(log, now_ms, EVENT_LEVEL_CLEARED, "FPGA HEARTBEAT OK");
        }
        else {
            psu_event_log_add(log, now_ms, EVENT_LEVEL_SHUTDOWN, "FPGA HEARTBEAT LOST");
        }
        log->last_fpga_alive = fpga_alive;
    }

    /* fault pins mean nothing while the FPGA is not running */
    if (!fpga_alive) {
        return;
    }

    if (fpga_fault != log->last_fpga_fault) {
        event_log_fault_change(log, now_ms, "FPGA ", log->last_fpga_fault, fpga_fault);
        log->last_fpga_fault = fpga_fault;
    }
}

/**
 * @brief Get a stored event, newest first.
 * @param log   Event log.
 * @param index 0 = newest.
 * @return Event, or NULL if there is no event at that index.
 */
const psu_event_t *psu_event_log_get(const psu_event_log_t *log, uint8_t index)
{
    uint8_t slot;

    if (index >= log->count) {
        return NULL;
    }

    slot = (uint8_t)((log->next + EVENT_LOG_SIZE - 1U - index) % EVENT_LOG_SIZE);
    return &log->entry[slot];
}

/**
 * @brief Short name of an FSM state.
 * @param state FSM state.
 * @return State name, "----" if unknown.
 */
const char *psu_event_log_state_name(psu_fsm_state_t state)
{
    switch (state) {
    case FSM_STATE_OFF:      return "OFF";
    case FSM_STATE_BOOT:     return "BOOT";
    case FSM_STATE_NORMAL:   return "NORMAL";
    case FSM_STATE_WARNING:  return "WARNING";
    case FSM_STATE_CRITICAL: return "CRITICAL";
    case FSM_STATE_SHUTDOWN: return "SHUTDOWN";
    case FSM_STATE_RECOVERY: return "RECOVERY";
    default:                 return "----";
    }
}

/**
 * @brief Short name of an FEE fault code.
 * @param code Fault code.
 * @return Fault name, "UNKNOWN" if not a fault code.
 */
const char *psu_event_log_fault_name(psu_fee_code_t code)
{
    switch (code) {
    case FEE_CODE_OVERCURRENT:           return "OVERCURRENT";
    case FEE_CODE_OVERVOLTAGE:           return "OVERVOLTAGE";
    case FEE_CODE_OVERTEMPERATURE:       return "OVERTEMP";
    case FEE_CODE_SENSOR_FAILURE:        return "SENSOR FAIL";
    case FEE_CODE_UNDERVOLTAGE:          return "UNDERVOLTAGE";
    case FEE_CODE_FAN_FAILURE:           return "FAN FAIL";
    case FEE_CODE_COMMUNICATION_TIMEOUT: return "COMM TIMEOUT";
    default:                             return "UNKNOWN";
    }
}

/**
 * @brief Event class of an FEE fault code, same classes as the FEE.
 * @param code Fault code.
 * @return Event level.
 */
psu_event_level_t psu_event_log_fault_level(psu_fee_code_t code)
{
    switch (code) {
    case FEE_CODE_OVERCURRENT:
    case FEE_CODE_OVERVOLTAGE:
        return EVENT_LEVEL_CRITICAL;
    case FEE_CODE_OVERTEMPERATURE:
    case FEE_CODE_SENSOR_FAILURE:
        return EVENT_LEVEL_SHUTDOWN;
    case FEE_CODE_UNDERVOLTAGE:
    case FEE_CODE_FAN_FAILURE:
    case FEE_CODE_COMMUNICATION_TIMEOUT:
        return EVENT_LEVEL_WARNING;
    default:
        return EVENT_LEVEL_INFO;
    }
}
