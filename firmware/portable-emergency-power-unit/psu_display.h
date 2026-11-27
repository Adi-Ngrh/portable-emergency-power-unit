#ifndef PSU_DISPLAY_H
#define PSU_DISPLAY_H

#include <stdint.h>
#include <stdbool.h>
#include "psu_power_sensor.h"
#include "psu_temperature_sensor.h"
#include "psu_fsm.h"
#include "psu_fee.h"
#include "psu_event_log.h"
#include "psu_ui_layout.h"

#ifdef __cplusplus
extern "C" {
#endif

/* on/off item that may not be known yet */
typedef enum
{
    DISPLAY_SWITCH_UNKNOWN = 0,   /* shown as "--" */
    DISPLAY_SWITCH_OFF,
    DISPLAY_SWITCH_ON
} psu_display_switch_t;

/* system status shown on screen, besides the sensor readings */
typedef struct
{
    psu_fsm_state_t      state;
    psu_fee_code_t       fault_code;        /* highest active fault */
    bool                 debug_mode;        /* MCU runs without the FPGA, see DEBUG_MODE in the .ino */
    bool                 fpga_alive;        /* FPGA heartbeat seen, fpga_fault_code is valid */
    psu_fee_code_t       fpga_fault_code;   /* highest active fault on the FPGA */
    int8_t               battery_percent;   /* 0 to 100, -1 = unknown */
    int8_t               wifi_level;        /* 0 to 3 bars, -1 = no Wi-Fi */
    psu_display_switch_t charge;            /* relay A, charging the PSU */
    psu_display_switch_t ac;                /* inverter output */
    psu_display_switch_t usb_a;
    psu_display_switch_t usb_c;
    psu_display_switch_t fan;
} psu_display_status_t;

/* values prepared for the display */
typedef struct
{
    int16_t  temperature;                         /* 1 LSB = 1/16 degC */
    int32_t  voltage_mv;
    int32_t  current_ma;
    int32_t  power_mw;
    bool     temperature_ok;                      /* temperature value is current */
    bool     power_ok;                            /* voltage, current, power values are current */
    uint32_t temperature_ms;                      /* time of last temperature update */
    uint32_t power_ms;                            /* time of last power update */
    uint32_t refresh_ms;                          /* time of last measurement text refresh */
    int8_t   battery_percent;                     /* battery icon level, -1 = unknown */
    int8_t   wifi_level;                          /* lit Wi-Fi bars, -1 = no Wi-Fi */
    char     text[UI_FIELD_COUNT][UI_TEXT_LEN];   /* text per field, e.g. "11.98V" */
    uint16_t fg[UI_FIELD_COUNT];                  /* text color per field */
    uint16_t bg[UI_FIELD_COUNT];                  /* background color per field */
} psu_display_data_t;

/* screen orientation 0 to 3, defined in psu_display.cpp */
extern uint8_t g_display_rotation;

/* drawing area width after rotation, defined in psu_display.cpp */
extern int16_t g_display_width;

/* drawing area height after rotation, defined in psu_display.cpp */
extern int16_t g_display_height;

void psu_display_screen_init(void);
void psu_display_status_init(psu_display_status_t *status);
void psu_display_init(psu_display_data_t *data);
void psu_display_update(psu_display_data_t *data,
                        const psu_power_reading_t *power,
                        const psu_temperature_reading_t *temperature,
                        const psu_display_status_t *status,
                        const psu_event_log_t *log);
void psu_display_ui_draw_static(void);
bool psu_display_ui_draw_next(const psu_display_data_t *data);

#ifdef __cplusplus
}
#endif

#endif
