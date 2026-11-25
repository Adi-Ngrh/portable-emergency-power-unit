#ifndef PSU_UI_LAYOUT_H
#define PSU_UI_LAYOUT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ==================== TEXT ==================== */

/* coordinates assume the area set by g_display_width/height in psu_display.cpp */
#define UI_TEXT_LEN       52    /* longest field text (log row) plus terminator */
#define UI_LOG_ROWS       6     /* event log lines on screen */

/* ==================== COLORS (RGB565) ==================== */

#define UI_COLOR_BG         0x08A2   /* screen background, #0b1414 */
#define UI_COLOR_BORDER     0x2A48   /* frames and separators, #2a4a46 */
#define UI_COLOR_TEXT       0xDF9D   /* main text, #d8f3ee */
#define UI_COLOR_DIM        0x7DD5   /* labels and fallback values, #7fb8ae */
#define UI_COLOR_ACCENT     0x5E54   /* active items, #5dcaa5 */
#define UI_COLOR_INACTIVE   0x3AEB   /* unknown or unused items, #3d5f5a */
#define UI_COLOR_BADGE_OFF  0x2207   /* OFF badges, dark enough for light text, #24403c */
#define UI_COLOR_ON_ACCENT  0x01A5   /* dark text on accent or green, #04342c */
#define UI_COLOR_GREEN      0x1CEE   /* NORMAL badge, #1d9e75 */
#define UI_COLOR_AMBER      0xECE4   /* warning, #ef9f27 */
#define UI_COLOR_ON_AMBER   0x4120   /* dark text on amber or yellow, #412402 */
#define UI_COLOR_YELLOW     0xFE2E   /* shutdown, #fac775 */
#define UI_COLOR_RED        0xA165   /* CRITICAL badge, dark enough for white text, #a32d2d */
#define UI_COLOR_LIGHT_RED  0xF4B2   /* critical log text, #f09595 */
#define UI_COLOR_WHITE      0xFFFF

/* ==================== ELEMENTS ==================== */

/* what an element draws */
typedef enum
{
    UI_FRAME,          /* static rectangle outline */
    UI_FILL,           /* static filled rectangle, used for separators */
    UI_LABEL,          /* static text */
    UI_VALUE,          /* live text, left aligned, padded to the box width */
    UI_BADGE,          /* live text centered on a live background color */
    UI_BATTERY_ICON,   /* live battery outline with fill level */
    UI_WIFI_ICON       /* live signal bars */
} psu_ui_type_t;

/* live values an element can show */
typedef enum
{
    UI_FIELD_NONE = 0,
    UI_FIELD_STATE,
    UI_FIELD_WIFI,
    UI_FIELD_BATTERY_ICON,
    UI_FIELD_BATTERY_PERCENT,
    UI_FIELD_VOLTAGE,
    UI_FIELD_CURRENT,
    UI_FIELD_POWER,
    UI_FIELD_TEMPERATURE,
    UI_FIELD_FAN,
    UI_FIELD_CHARGE,
    UI_FIELD_AC,
    UI_FIELD_USB_A,
    UI_FIELD_USB_C,
    UI_FIELD_ACTIVE_FAULT,
    UI_FIELD_LOG_0,                                  /* newest event, rows follow in order */
    UI_FIELD_COUNT = UI_FIELD_LOG_0 + UI_LOG_ROWS
} psu_ui_field_t;

/* one screen element */
typedef struct
{
    psu_ui_type_t  type;
    int16_t        x;
    int16_t        y;
    int16_t        w;
    int16_t        h;
    uint16_t       color;       /* frame, fill or label color */
    uint8_t        text_size;   /* GFX text size, 1 char = 6*size x 8*size px */
    const char    *text;        /* label text, NULL for others */
    psu_ui_field_t field;       /* live value, UI_FIELD_NONE for static elements */
} psu_ui_element_t;

/* screen layout table, defined in psu_ui_layout.c */
extern const psu_ui_element_t g_ui_layout[];

/* number of elements in g_ui_layout, defined in psu_ui_layout.c */
extern const uint16_t g_ui_layout_count;

#ifdef __cplusplus
}
#endif

#endif
