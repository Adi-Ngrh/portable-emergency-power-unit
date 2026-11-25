/*
 * Arduino core functions used:
 *   millis()
 */

#include "psu_fsm.h"
#include "psu_fee.h"
#include "psu_board.h"
#include "psu_power_sensor.h"
#include "psu_temperature_sensor.h"
#include "psu_display.h"
#include "psu_event_log.h"

/* FSM instance struct from psu_fsm.h */
psu_fsm_t g_fsm;

/* FEE instance struct from psu_fee.h */
psu_fee_t g_fee;

/* FSM inputs struct from psu_fsm.h, starts zeroed */
psu_fsm_inputs_t g_fsm_in;

/* FEE inputs struct from psu_fee.h, starts zeroed */
psu_fee_inputs_t g_fee_in;

/* power reading struct from psu_power_sensor.h */
psu_power_reading_t g_power_reading;

/* temperature reading struct from psu_temperature_sensor.h */
psu_temperature_reading_t g_temp_reading;

/* display data struct from psu_display.h */
psu_display_data_t g_display;

/* status shown on screen, struct from psu_display.h */
psu_display_status_t g_display_status;

/* event log ring buffer struct from psu_event_log.h */
psu_event_log_t g_event_log;

void setup()
{
    psu_fsm_init(&g_fsm);
    psu_fee_init(&g_fee);
    psu_event_log_init(&g_event_log);
    psu_display_status_init(&g_display_status);
    psu_display_init(&g_display);

    /* screen and static UI parts */
    psu_display_screen_init();
    psu_display_ui_draw_static();
}

void loop()
{
    /* main system boot, BOOT always ends on this update */
    g_fsm_in.boot_passed = false;
    g_fsm_in.boot_failed = false;
    if (g_fsm.state == FSM_STATE_BOOT) {
        if (psu_board_init()) {
            g_fsm_in.boot_passed = true;
        }
        else {
            g_fsm_in.boot_failed = true;
        }
    }

    /* sensors only while main system is up */
    if (g_fsm.state == FSM_STATE_NORMAL ||
        g_fsm.state == FSM_STATE_WARNING ||
        g_fsm.state == FSM_STATE_SHUTDOWN) {
        psu_power_read(&g_power_reading);
        psu_temperature_read(&g_temp_reading);
    }
    else {
        g_power_reading.valid = false;
        g_power_reading.error = false;
        g_temp_reading.valid  = false;
        g_temp_reading.error  = false;
    }

    /* temperature -> FEE */
    g_fee_in.temperature       = g_temp_reading.temperature;
    g_fee_in.temperature_valid = g_temp_reading.valid;
    g_fee_in.temperature_error = g_temp_reading.error;

    /* FSM -> FEE */
    g_fee_in.critical_clear = g_fsm.out.critical_clear;

    psu_fee_update(&g_fee, &g_fee_in);

    /* FEE -> FSM */
    g_fsm_in.warning_request  = g_fee.out.warning_response;
    g_fsm_in.shutdown_request = g_fee.out.shutdown_response;
    g_fsm_in.critical_request = g_fee.out.critical_response;

    psu_fsm_update(&g_fsm, &g_fsm_in);

    /* state and fault changes -> event log */
    psu_event_log_track(&g_event_log, millis(), g_fsm.state, g_fee.out.fault_code);

    /* status -> display, ports and fan stay OFF, battery and Wi-Fi unknown until their code exists */
    g_display_status.state      = g_fsm.state;
    g_display_status.fault_code = g_fee.out.fault_code;

    /* readings -> display, then redraw at most one changed element */
    psu_display_update(&g_display, &g_power_reading, &g_temp_reading, &g_display_status, &g_event_log);
    psu_display_ui_draw_next(&g_display);
}
