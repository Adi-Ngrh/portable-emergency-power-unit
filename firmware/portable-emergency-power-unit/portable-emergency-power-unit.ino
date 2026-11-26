/*
 * Arduino core functions used:
 *   millis()
 */

#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/queue.h>
#include "psu_fsm.h"
#include "psu_fee.h"
#include "psu_board.h"
#include "psu_power_sensor.h"
#include "psu_temperature_sensor.h"
#include "psu_display.h"
#include "psu_event_log.h"
#include "psu_mcu_heartbeat.h"
#include "psu_mcu_status.h"
#include "psu_fpga_heartbeat.h"
#include "psu_power_switch.h"
#include "psu_fpga_fault.h"
#include "psu_battery.h"

/* ==================== TASK SETTINGS ==================== */

/* all tasks on the app core, core 0 is left for Wi-Fi */
#define TASK_CORE                  1

/* stack sizes are in bytes on the ESP32 */
#define CONTROL_TASK_STACK_BYTES   4096
#define SENSOR_TASK_STACK_BYTES    4096
#define DISPLAY_TASK_STACK_BYTES   4096

/* higher number runs first, so FSM and FEE never wait for slow I/O */
#define CONTROL_TASK_PRIORITY      3
#define SENSOR_TASK_PRIORITY       2
#define DISPLAY_TASK_PRIORITY      1

/* task timing */
#define CONTROL_TASK_PERIOD_MS     1     /* one FSM/FEE update per tick, FEE windows start at 1 ms */
#define SENSOR_TASK_PERIOD_MS      10    /* drivers pace themselves (power 36 ms, temperature 750 ms) */
#define DISPLAY_WAIT_MS            100   /* longest wait for a reading, screen keeps updating */

/* queue lengths */
#define BOOT_RESULT_QUEUE_LEN      2
#define CONTROL_READINGS_QUEUE_LEN 4     /* control takes one every 1 ms, sensor sends one every ~10 ms */
#define DISPLAY_READINGS_QUEUE_LEN 32    /* holds readings while a slow redraw runs */

/* ==================== MESSAGES BETWEEN TASKS ==================== */

/* sensor readings, sensor task -> control task and display task */
typedef struct
{
    psu_power_reading_t       power;
    psu_temperature_reading_t temperature;
} psu_sensor_readings_t;

/* orders for the sensor task, control task -> sensor task */
typedef struct
{
    bool     read_enabled;   /* main system is up, read the sensors */
    uint32_t boot_attempt;   /* changes on every BOOT entry, run the main system init once */
} psu_sensor_command_t;

/* main system init result, sensor task -> control task */
typedef struct
{
    uint32_t boot_attempt;   /* BOOT attempt this result belongs to */
    bool     passed;         /* every sensor responded */
} psu_boot_result_t;

/* status and event log, control task -> display task */
typedef struct
{
    psu_display_status_t status;
    psu_event_log_t      log;
} psu_status_report_t;

/* ==================== QUEUES ==================== */

/* sensor command mailbox (newest only), handle type from FreeRTOS queue.h */
static QueueHandle_t g_sensor_command_queue = NULL;

/* boot result queue, handle type from FreeRTOS queue.h */
static QueueHandle_t g_boot_result_queue = NULL;

/* readings queue for the control task, handle type from FreeRTOS queue.h */
static QueueHandle_t g_control_readings_queue = NULL;

/* readings queue for the display task, handle type from FreeRTOS queue.h */
static QueueHandle_t g_display_readings_queue = NULL;

/* status report mailbox (newest only), handle type from FreeRTOS queue.h */
static QueueHandle_t g_status_report_queue = NULL;

/* ==================== TASK DECLARATIONS ==================== */

static void control_task(void *param);
static void control_update(void);
static void sensor_task(void *param);
static void display_task(void *param);

/* ==================== SETUP AND LOOP ==================== */

void setup()
{
    /* queues first, a task can run as soon as it is created */
    g_sensor_command_queue   = xQueueCreate(1, sizeof(psu_sensor_command_t));
    g_boot_result_queue      = xQueueCreate(BOOT_RESULT_QUEUE_LEN, sizeof(psu_boot_result_t));
    g_control_readings_queue = xQueueCreate(CONTROL_READINGS_QUEUE_LEN, sizeof(psu_sensor_readings_t));
    g_display_readings_queue = xQueueCreate(DISPLAY_READINGS_QUEUE_LEN, sizeof(psu_sensor_readings_t));
    g_status_report_queue    = xQueueCreate(1, sizeof(psu_status_report_t));

    xTaskCreatePinnedToCore(control_task, "control", CONTROL_TASK_STACK_BYTES, NULL,
                            CONTROL_TASK_PRIORITY, NULL, TASK_CORE);
    xTaskCreatePinnedToCore(sensor_task, "sensor", SENSOR_TASK_STACK_BYTES, NULL,
                            SENSOR_TASK_PRIORITY, NULL, TASK_CORE);
    xTaskCreatePinnedToCore(display_task, "display", DISPLAY_TASK_STACK_BYTES, NULL,
                            DISPLAY_TASK_PRIORITY, NULL, TASK_CORE);
}

void loop()
{
    /* Arduino loop task is not needed, delete it */
    vTaskDelete(NULL);
}

/* ==================== CONTROL TASK ==================== */

/* FSM instance struct from psu_fsm.h */
static psu_fsm_t g_fsm;

/* FEE instance struct from psu_fee.h */
static psu_fee_t g_fee;

/* FSM inputs struct from psu_fsm.h, starts zeroed */
static psu_fsm_inputs_t g_fsm_in;

/* FEE inputs struct from psu_fee.h, starts zeroed */
static psu_fee_inputs_t g_fee_in;

/* latest sensor readings at the control task, struct defined above, starts zeroed */
static psu_sensor_readings_t g_control_readings;

/* event log ring buffer struct from psu_event_log.h */
static psu_event_log_t g_event_log;

/* status shown on screen, struct from psu_display.h */
static psu_display_status_t g_display_status;

/* orders sent to the sensor task, struct defined above */
static psu_sensor_command_t g_sensor_command;

/* status and log sent to the display task, struct defined above */
static psu_status_report_t g_status_report;

/* number of the current BOOT attempt, 0 = no BOOT yet */
static uint32_t g_boot_attempt = 0;

/**
 * @brief Control task: runs the FSM and FEE every CONTROL_TASK_PERIOD_MS.
 * @param param Unused task argument.
 */
static void control_task(void *param)
{
    /* tick count type from FreeRTOS.h */
    TickType_t wake_tick;

    (void)param;

    psu_fsm_init(&g_fsm);
    psu_fee_init(&g_fee);
    psu_event_log_init(&g_event_log);
    psu_display_status_init(&g_display_status);
    psu_mcu_heartbeat_init();
    psu_mcu_status_init();
    psu_fpga_heartbeat_init();
    psu_power_switch_init();
    psu_fpga_fault_init();

    wake_tick = xTaskGetTickCount();
    for (;;) {
        control_update();

        /* fixed period */
        xTaskDelayUntil(&wake_tick, pdMS_TO_TICKS(CONTROL_TASK_PERIOD_MS));
    }
}

/**
 * @brief One control update: inputs from the sensor task, FEE, FSM, event log, outputs to the other tasks.
 */
static void control_update(void)
{
    /* FSM state enum from psu_fsm.h */
    psu_fsm_state_t   previous_state = g_fsm.state;
    /* boot result struct defined above */
    psu_boot_result_t boot_result;
    /* fault code enum from psu_fee.h */
    psu_fee_code_t    fpga_fault;
    uint32_t          now_ms;
    bool              main_system_up;

    /* main system init result, a result of an older BOOT attempt is ignored */
    g_fsm_in.boot_passed = false;
    g_fsm_in.boot_failed = false;
    if (xQueueReceive(g_boot_result_queue, &boot_result, 0) == pdTRUE) {
        if (g_fsm.state == FSM_STATE_BOOT && boot_result.boot_attempt == g_boot_attempt) {
            if (boot_result.passed) {
                g_fsm_in.boot_passed = true;
            }
            else {
                g_fsm_in.boot_failed = true;
            }
        }
    }

    /* newest readings, without one nothing is new this update (error flags kept) */
    if (xQueueReceive(g_control_readings_queue, &g_control_readings, 0) != pdTRUE) {
        g_control_readings.power.valid       = false;
        g_control_readings.temperature.valid = false;
    }

    /* FPGA heartbeat -> FSM, BOOT only while the FPGA safety monitor is alive */
    g_fsm_in.fpga_alive = psu_fpga_heartbeat_update();

    /* FPGA fault code, only shown and logged (the FPGA cuts power by itself) */
    fpga_fault = psu_fpga_fault_update();

    /* power switch -> FSM, the FSM acts on OFF -> ON only */
    g_fsm_in.manual_power = psu_power_switch_update();

    /* main system shutdown: nothing to switch off yet, so it is done at once (replace with relay code) */
    g_fsm_in.shutdown_done = (g_fsm.state == FSM_STATE_SHUTDOWN);

    /* temperature -> FEE */
    g_fee_in.temperature       = g_control_readings.temperature.temperature;
    g_fee_in.temperature_valid = g_control_readings.temperature.valid;
    g_fee_in.temperature_error = g_control_readings.temperature.error;

    /* FSM -> FEE */
    g_fee_in.critical_clear = g_fsm.out.critical_clear;

    psu_fee_update(&g_fee, &g_fee_in);

    /* FEE -> FSM */
    g_fsm_in.warning_request  = g_fee.out.warning_response;
    g_fsm_in.shutdown_request = g_fee.out.shutdown_response;
    g_fsm_in.critical_request = g_fee.out.critical_response;

    psu_fsm_update(&g_fsm, &g_fsm_in);

    /* FSM -> FPGA, heartbeat stops if this task stops */
    psu_mcu_heartbeat_update(g_fsm.out.mcu_heartbeat);
    psu_mcu_status_update(g_fsm.out.boot_success, g_fsm.out.shutdown_success);

    /* new BOOT attempt, the sensor task runs the main system init once for it */
    if (g_fsm.state == FSM_STATE_BOOT && previous_state != FSM_STATE_BOOT) {
        g_boot_attempt++;
    }

    /* FPGA changes, then MCU changes -> event log (cause is logged before the state change) */
    now_ms = millis();
    psu_event_log_track_fpga(&g_event_log, now_ms, g_fsm_in.fpga_alive, fpga_fault);
    psu_event_log_track(&g_event_log, now_ms, g_fsm.state, g_fee.out.fault_code);

    /* main system is up: sensors are read and the battery level is known */
    main_system_up = (g_fsm.state == FSM_STATE_NORMAL ||
                      g_fsm.state == FSM_STATE_WARNING ||
                      g_fsm.state == FSM_STATE_SHUTDOWN);

    /* status -> display, ports and fan stay OFF, Wi-Fi unknown until their code exists */
    g_display_status.state           = g_fsm.state;
    g_display_status.fault_code      = g_fee.out.fault_code;
    g_display_status.fpga_alive      = g_fsm_in.fpga_alive;
    g_display_status.fpga_fault_code = fpga_fault;

    /* battery level from the INA226 voltage, unknown while the main system is off or the sensor fails */
    if (!main_system_up || g_control_readings.power.error) {
        g_display_status.battery_percent = -1;
    }
    else if (g_control_readings.power.valid) {
        g_display_status.battery_percent = psu_battery_percent(g_control_readings.power.voltage_mv);
    }

    /* orders -> sensor task, sensors only while main system is up */
    g_sensor_command.read_enabled = main_system_up;
    g_sensor_command.boot_attempt = g_boot_attempt;
    xQueueOverwrite(g_sensor_command_queue, &g_sensor_command);

    /* status and log -> display task */
    g_status_report.status = g_display_status;
    g_status_report.log    = g_event_log;
    xQueueOverwrite(g_status_report_queue, &g_status_report);
}

/* ==================== SENSOR TASK ==================== */

/* orders received from the control task, struct defined above, starts zeroed (no reads, no BOOT) */
static psu_sensor_command_t g_sensor_task_command;

/* sensor readings, struct defined above, starts zeroed */
static psu_sensor_readings_t g_sensor_readings;

/* main system init result, struct defined above */
static psu_boot_result_t g_boot_result;

/* last BOOT attempt the main system init ran for */
static uint32_t g_boot_attempt_done = 0;

/**
 * @brief Sensor task: main system init on BOOT, sensor reads while the main system is up.
 * @param param Unused task argument.
 */
static void sensor_task(void *param)
{
    (void)param;

    for (;;) {
        /* newest orders from the control task, old ones kept if none yet */
        xQueuePeek(g_sensor_command_queue, &g_sensor_task_command, 0);

        /* main system init, once per BOOT attempt */
        if (g_sensor_task_command.boot_attempt != g_boot_attempt_done) {
            g_boot_result.boot_attempt = g_sensor_task_command.boot_attempt;
            g_boot_result.passed       = psu_board_init();
            g_boot_attempt_done        = g_sensor_task_command.boot_attempt;
            xQueueSend(g_boot_result_queue, &g_boot_result, 0);
        }

        /* sensors only while main system is up */
        if (g_sensor_task_command.read_enabled) {
            psu_power_read(&g_sensor_readings.power);
            psu_temperature_read(&g_sensor_readings.temperature);
        }
        else {
            g_sensor_readings.power.valid       = false;
            g_sensor_readings.power.error       = false;
            g_sensor_readings.temperature.valid = false;
            g_sensor_readings.temperature.error = false;
        }

        /* readings -> control task and display task, never wait on a full queue */
        xQueueSend(g_control_readings_queue, &g_sensor_readings, 0);
        xQueueSend(g_display_readings_queue, &g_sensor_readings, 0);

        /* plain delay, so a long init is not followed by a burst of catch-up loops */
        vTaskDelay(pdMS_TO_TICKS(SENSOR_TASK_PERIOD_MS));
    }
}

/* ==================== DISPLAY TASK ==================== */

/* display data struct from psu_display.h */
static psu_display_data_t g_display;

/* latest sensor readings at the display task, struct defined above, starts zeroed */
static psu_sensor_readings_t g_display_readings;

/* latest status and event log at the display task, struct defined above */
static psu_status_report_t g_display_report;

/**
 * @brief Display task: owns the screen, redraws at most one changed field per reading.
 * @param param Unused task argument.
 */
static void display_task(void *param)
{
    (void)param;

    /* shown until the first report from the control task */
    psu_display_status_init(&g_display_report.status);
    psu_event_log_init(&g_display_report.log);
    psu_display_init(&g_display);

    /* screen and static UI parts */
    psu_display_screen_init();
    psu_display_ui_draw_static();

    for (;;) {
        /* next reading, without one nothing is new (error flags kept) */
        if (xQueueReceive(g_display_readings_queue, &g_display_readings,
                          pdMS_TO_TICKS(DISPLAY_WAIT_MS)) != pdTRUE) {
            g_display_readings.power.valid       = false;
            g_display_readings.temperature.valid = false;
        }

        /* newest status and log, old ones kept if none yet */
        xQueuePeek(g_status_report_queue, &g_display_report, 0);

        /* readings -> display, then redraw at most one changed element */
        psu_display_update(&g_display, &g_display_readings.power, &g_display_readings.temperature,
                           &g_display_report.status, &g_display_report.log);
        psu_display_ui_draw_next(&g_display);
    }
}
