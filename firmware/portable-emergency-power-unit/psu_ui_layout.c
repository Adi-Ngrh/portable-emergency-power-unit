#include <stddef.h>
#include "psu_ui_layout.h"

/* log row position: first row top, distance between rows */
#define LOG_Y0     164
#define LOG_PITCH  11

/* screen layout table (type, x, y, w, h, color, size, text, field) from psu_ui_layout.h */
const psu_ui_element_t g_ui_layout[] = {

    /* header */
    { UI_LABEL,        4,   7,   114, 8,  UI_COLOR_TEXT,     1, "PORTABLE POWER UNIT", UI_FIELD_NONE },
    { UI_WIFI_ICON,    239, 3,   22,  16, UI_COLOR_INACTIVE, 0, NULL,                  UI_FIELD_WIFI },
    { UI_BADGE,        264, 3,   53,  16, UI_COLOR_TEXT,     1, NULL,                  UI_FIELD_STATE },
    { UI_FILL,         0,   22,  320, 1,  UI_COLOR_BORDER,   0, NULL,                  UI_FIELD_NONE },

    /* battery tile */
    { UI_FRAME,        2,   26,  200, 68, UI_COLOR_BORDER,   0, NULL,                  UI_FIELD_NONE },
    { UI_LABEL,        8,   30,  42,  8,  UI_COLOR_DIM,      1, "BATTERY",             UI_FIELD_NONE },
    { UI_BATTERY_ICON, 8,   53,  31,  15, UI_COLOR_ACCENT,   0, NULL,                  UI_FIELD_BATTERY_ICON },
    { UI_VALUE,        46,  57,  48,  8,  UI_COLOR_TEXT,     1, NULL,                  UI_FIELD_BATTERY_PERCENT },
    { UI_FILL,         104, 30,  1,   60, UI_COLOR_BORDER,   0, NULL,                  UI_FIELD_NONE },
    { UI_VALUE,        110, 34,  84,  8,  UI_COLOR_TEXT,     1, NULL,                  UI_FIELD_VOLTAGE },
    { UI_VALUE,        110, 53,  84,  8,  UI_COLOR_TEXT,     1, NULL,                  UI_FIELD_CURRENT },
    { UI_VALUE,        110, 72,  84,  8,  UI_COLOR_TEXT,     1, NULL,                  UI_FIELD_POWER },

    /* temperature tile */
    { UI_FRAME,        206, 26,  112, 68, UI_COLOR_BORDER,   0, NULL,                  UI_FIELD_NONE },
    { UI_LABEL,        212, 30,  84,  8,  UI_COLOR_DIM,      1, "TEMP (HOTTEST)",      UI_FIELD_NONE },
    { UI_VALUE,        212, 48,  84,  8,  UI_COLOR_TEXT,     1, NULL,                  UI_FIELD_TEMPERATURE },
    { UI_VALUE,        212, 70,  84,  8,  UI_COLOR_TEXT,     1, NULL,                  UI_FIELD_FAN },

    /* ports, 2 x 2 */
    { UI_FRAME,        2,   98,  316, 46, UI_COLOR_BORDER,   0, NULL,                  UI_FIELD_NONE },
    { UI_LABEL,        8,   117, 30,  8,  UI_COLOR_DIM,      1, "PORTS",               UI_FIELD_NONE },
    { UI_BADGE,        42,  102, 134, 18, UI_COLOR_TEXT,     1, NULL,                  UI_FIELD_CHARGE },
    { UI_BADGE,        180, 102, 134, 18, UI_COLOR_TEXT,     1, NULL,                  UI_FIELD_AC },
    { UI_BADGE,        42,  122, 134, 18, UI_COLOR_TEXT,     1, NULL,                  UI_FIELD_USB_A },
    { UI_BADGE,        180, 122, 134, 18, UI_COLOR_TEXT,     1, NULL,                  UI_FIELD_USB_C },

    /* event log */
    { UI_FRAME,        2,   148, 316, 90, UI_COLOR_BORDER,   0, NULL,                  UI_FIELD_NONE },
    { UI_LABEL,        8,   152, 108, 8,  UI_COLOR_DIM,      1, "EVENT LOG (UPTIME)",  UI_FIELD_NONE },
    { UI_VALUE,        164, 152, 72,  8,  UI_COLOR_DIM,      1, NULL,                  UI_FIELD_FPGA_FAULT },
    { UI_VALUE,        242, 152, 72,  8,  UI_COLOR_DIM,      1, NULL,                  UI_FIELD_ACTIVE_FAULT },
    { UI_VALUE,        8,   LOG_Y0 + 0 * LOG_PITCH, 300, 8, UI_COLOR_TEXT, 1, NULL,  UI_FIELD_LOG_0 + 0 },
    { UI_VALUE,        8,   LOG_Y0 + 1 * LOG_PITCH, 300, 8, UI_COLOR_TEXT, 1, NULL,  UI_FIELD_LOG_0 + 1 },
    { UI_VALUE,        8,   LOG_Y0 + 2 * LOG_PITCH, 300, 8, UI_COLOR_TEXT, 1, NULL,  UI_FIELD_LOG_0 + 2 },
    { UI_VALUE,        8,   LOG_Y0 + 3 * LOG_PITCH, 300, 8, UI_COLOR_TEXT, 1, NULL,  UI_FIELD_LOG_0 + 3 },
    { UI_VALUE,        8,   LOG_Y0 + 4 * LOG_PITCH, 300, 8, UI_COLOR_TEXT, 1, NULL,  UI_FIELD_LOG_0 + 4 },
    { UI_VALUE,        8,   LOG_Y0 + 5 * LOG_PITCH, 300, 8, UI_COLOR_TEXT, 1, NULL,  UI_FIELD_LOG_0 + 5 }
};

/* number of elements in g_ui_layout */
const uint16_t g_ui_layout_count = (uint16_t)(sizeof(g_ui_layout) / sizeof(g_ui_layout[0]));
