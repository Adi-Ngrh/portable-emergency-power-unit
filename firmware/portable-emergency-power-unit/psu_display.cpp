/*
 * Arduino core functions used:
 *   millis()
 *   pinMode()
 *   digitalWrite()
 */

#include <Arduino.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <SPI.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ILI9341.h>
#include "psu_board.h"
#include "psu_display.h"

/* screen settings */
#define DISPLAY_SPI_HZ        6000000UL   /* safe start value, raise later for speed */

/* decimals shown per value */
#define DISPLAY_VOLTAGE_DECIMALS      2
#define DISPLAY_CURRENT_DECIMALS      2
#define DISPLAY_POWER_DECIMALS        1
#define DISPLAY_TEMPERATURE_DECIMALS  1   /* sensor accuracy is 0.5 degC */

/* value shown as "--" after this long without an update */
#define DISPLAY_POWER_STALE_MS        500UL    /* power reads every 36 ms */
#define DISPLAY_TEMPERATURE_STALE_MS  2000UL   /* temperature reads every ~750 ms */

/* measurement texts refresh at most this often, limits redraw time */
#define DISPLAY_REFRESH_MS            250UL

/* ==================== SCREEN SETTINGS (tweak here) ==================== */

/* orientation, 0 to 3, each step turns the image 90 degrees */
uint8_t g_display_rotation = 0;

/* drawing area width after rotation, in pixels */
int16_t g_display_width = 320;

/* drawing area height after rotation, in pixels */
int16_t g_display_height = 240;

/* ==================== SCREEN DRIVER ==================== */

/* ILI9341 driver object from Adafruit_ILI9341.h, on the VSPI bus from SPI.h */
static Adafruit_ILI9341 g_tft(&SPI, (int8_t)TFT_DC_PIN, (int8_t)TFT_CS_PIN, (int8_t)TFT_RST_PIN);

/**
 * @brief Set the panel orientation and the library drawing size.
 * @param rotation Panel orientation 0 to 3, 0 and 2 are landscape on this panel.
 */
static void display_set_rotation(uint8_t rotation)
{
    uint8_t madctl;

    /* step 1: library drawing size, it gives 320x240 only at rotation 1 and 3 */
    if (rotation == 0 || rotation == 2) {
        g_tft.setRotation((uint8_t)1);   /* landscape size 320x240 */
    }
    else {
        g_tft.setRotation((uint8_t)0);   /* portrait size 240x320 */
    }

    /* step 2: panel orientation, setRotation() above sent its own, so send ours after it */
    if (rotation == 0) {
        madctl = 0x48;   /* same command the library sends for rotation 0 */
    }
    else if (rotation == 1) {
        madctl = 0x28;   /* same command the library sends for rotation 1 */
    }
    else if (rotation == 2) {
        madctl = 0x88;   /* same command the library sends for rotation 2 */
    }
    else {
        madctl = 0xE8;   /* same command the library sends for rotation 3 */
    }
    g_tft.sendCommand((uint8_t)ILI9341_MADCTL, &madctl, (uint8_t)1);
}

/**
 * @brief Start the SPI bus and the screen, set the orientation, turn the backlight on.
 */
void psu_display_screen_init(void)
{
    /* backlight */
    pinMode((uint8_t)TFT_LED_PIN, (uint8_t)OUTPUT);
    digitalWrite((uint8_t)TFT_LED_PIN, (uint8_t)HIGH);

    /* SPI bus and controller */
    SPI.begin((int8_t)TFT_SCK_PIN, (int8_t)TFT_MISO_PIN, (int8_t)TFT_MOSI_PIN, (int8_t)TFT_CS_PIN);
    g_tft.begin((uint32_t)DISPLAY_SPI_HZ);
    display_set_rotation(g_display_rotation);
}

/* ==================== DATA LAYER ==================== */

/**
 * @brief Format a milli-unit value as fixed-point text, rounded.
 * @param[out] text Output text.
 * @param len       Size of text.
 * @param milli     Value in milli-units (mV, mA, mW, m-degC).
 * @param decimals  Digits after the point, 1 or 2.
 * @param unit      Unit appended right after the number.
 */
static void display_format(char *text, size_t len, int32_t milli, int decimals, const char *unit)
{
    int32_t     step;
    int32_t     scale;
    int32_t     magnitude;
    int32_t     units;
    const char *sign;

    /* step: milli-units per shown digit, scale: shown digits per unit */
    if (decimals == 1) {
        step  = 100;
        scale = 10;
    }
    else {
        step  = 10;
        scale = 100;
    }

    magnitude = (milli < 0) ? -milli : milli;
    units     = (magnitude + step / 2) / step;

    /* no "-0.00" when the value rounds to zero */
    sign = (milli < 0 && units != 0) ? "-" : "";

    snprintf(text, len, "%s%ld.%0*ld%s",
             sign, (long)(units / scale), decimals, (long)(units % scale), unit);
}

/**
 * @brief Set the text and colors of one field.
 * @param[in,out] data Display data.
 * @param field        Field to set.
 * @param text         New text.
 * @param fg           Text color.
 * @param bg           Background color.
 */
static void display_set_field(psu_display_data_t *data, psu_ui_field_t field,
                              const char *text, uint16_t fg, uint16_t bg)
{
    snprintf(data->text[field], UI_TEXT_LEN, "%s", text);
    data->fg[field] = fg;
    data->bg[field] = bg;
}

/**
 * @brief Text color for an event class.
 * @param level Event class.
 * @return RGB565 color.
 */
static uint16_t display_level_color(psu_event_level_t level)
{
    switch (level) {
    case EVENT_LEVEL_CLEARED:  return UI_COLOR_DIM;
    case EVENT_LEVEL_WARNING:  return UI_COLOR_AMBER;
    case EVENT_LEVEL_SHUTDOWN: return UI_COLOR_YELLOW;
    case EVENT_LEVEL_CRITICAL: return UI_COLOR_LIGHT_RED;
    default:                   return UI_COLOR_TEXT;
    }
}

/**
 * @brief Fill a port badge: "--" when unknown, OFF, or ON.
 * @param[in,out] data Display data.
 * @param field        Badge field.
 * @param name         Port name, e.g. "CHARGE".
 * @param state        Port state.
 */
static void display_set_switch_badge(psu_display_data_t *data, psu_ui_field_t field,
                                     const char *name, psu_display_switch_t state)
{
    char text[UI_TEXT_LEN];

    if (state == DISPLAY_SWITCH_ON) {
        snprintf(text, sizeof(text), "%s ON", name);
        display_set_field(data, field, text, UI_COLOR_ON_ACCENT, UI_COLOR_ACCENT);
    }
    else if (state == DISPLAY_SWITCH_OFF) {
        snprintf(text, sizeof(text), "%s OFF", name);
        display_set_field(data, field, text, UI_COLOR_TEXT, UI_COLOR_BADGE_OFF);
    }
    else {
        snprintf(text, sizeof(text), "%s --", name);
        display_set_field(data, field, text, UI_COLOR_DIM, UI_COLOR_BORDER);
    }
}

/**
 * @brief Refresh voltage, current, power and temperature texts, "--" when not current.
 * @param[in,out] data Display data.
 */
static void display_measurement_texts(psu_display_data_t *data)
{
    char text[UI_TEXT_LEN];

    if (data->power_ok) {
        display_format(text, sizeof(text), data->voltage_mv, DISPLAY_VOLTAGE_DECIMALS, "V");
        display_set_field(data, UI_FIELD_VOLTAGE, text, UI_COLOR_TEXT, UI_COLOR_BG);
        display_format(text, sizeof(text), data->current_ma, DISPLAY_CURRENT_DECIMALS, "A");
        display_set_field(data, UI_FIELD_CURRENT, text, UI_COLOR_TEXT, UI_COLOR_BG);
        display_format(text, sizeof(text), data->power_mw, DISPLAY_POWER_DECIMALS, "W");
        display_set_field(data, UI_FIELD_POWER, text, UI_COLOR_TEXT, UI_COLOR_BG);
    }
    else {
        display_set_field(data, UI_FIELD_VOLTAGE, "-- V", UI_COLOR_DIM, UI_COLOR_BG);
        display_set_field(data, UI_FIELD_CURRENT, "-- A", UI_COLOR_DIM, UI_COLOR_BG);
        display_set_field(data, UI_FIELD_POWER, "-- W", UI_COLOR_DIM, UI_COLOR_BG);
    }

    if (data->temperature_ok) {
        /* 1/16 degC to m-degC */
        display_format(text, sizeof(text), (int32_t)data->temperature * 1000L / 16L,
                       DISPLAY_TEMPERATURE_DECIMALS, "C");
        display_set_field(data, UI_FIELD_TEMPERATURE, text, UI_COLOR_TEXT, UI_COLOR_BG);
    }
    else {
        display_set_field(data, UI_FIELD_TEMPERATURE, "-- C", UI_COLOR_DIM, UI_COLOR_BG);
    }
}

/**
 * @brief Refresh state, battery, Wi-Fi, fan, port, active fault and FPGA fault fields.
 * @param[in,out] data Display data.
 * @param status       System status.
 */
static void display_status_texts(psu_display_data_t *data, const psu_display_status_t *status)
{
    char     text[UI_TEXT_LEN];
    uint16_t fg;
    uint16_t bg;

    /* state badge */
    switch (status->state) {
    case FSM_STATE_OFF:      fg = UI_COLOR_TEXT;      bg = UI_COLOR_BADGE_OFF; break;
    case FSM_STATE_BOOT:     fg = UI_COLOR_ON_ACCENT; bg = UI_COLOR_ACCENT;    break;
    case FSM_STATE_NORMAL:   fg = UI_COLOR_ON_ACCENT; bg = UI_COLOR_GREEN;     break;
    case FSM_STATE_WARNING:  fg = UI_COLOR_ON_AMBER;  bg = UI_COLOR_AMBER;     break;
    case FSM_STATE_CRITICAL: fg = UI_COLOR_WHITE;     bg = UI_COLOR_RED;       break;
    case FSM_STATE_SHUTDOWN: fg = UI_COLOR_ON_AMBER;  bg = UI_COLOR_YELLOW;    break;
    case FSM_STATE_RECOVERY: fg = UI_COLOR_ON_ACCENT; bg = UI_COLOR_DIM;       break;
    default:                 fg = UI_COLOR_TEXT;      bg = UI_COLOR_BADGE_OFF; break;
    }
    display_set_field(data, UI_FIELD_STATE, psu_event_log_state_name(status->state), fg, bg);

    /* battery, -1 or out of range = unknown */
    if (status->battery_percent >= 0 && status->battery_percent <= 100) {
        data->battery_percent = status->battery_percent;
        snprintf(text, sizeof(text), "%d%%", (int)status->battery_percent);
        display_set_field(data, UI_FIELD_BATTERY_PERCENT, text, UI_COLOR_TEXT, UI_COLOR_BG);
    }
    else {
        data->battery_percent = -1;
        display_set_field(data, UI_FIELD_BATTERY_PERCENT, "--%", UI_COLOR_DIM, UI_COLOR_BG);
    }

    /* icon texts only mark a change for the drawer */
    snprintf(text, sizeof(text), "%d", (int)data->battery_percent);
    display_set_field(data, UI_FIELD_BATTERY_ICON, text, UI_COLOR_ACCENT, UI_COLOR_BG);

    /* Wi-Fi, -1 or out of range = no Wi-Fi */
    data->wifi_level = (status->wifi_level >= 0 && status->wifi_level <= 3) ? status->wifi_level : (int8_t)-1;
    snprintf(text, sizeof(text), "%d", (int)data->wifi_level);
    display_set_field(data, UI_FIELD_WIFI, text, UI_COLOR_ACCENT, UI_COLOR_BG);

    /* fan */
    if (status->fan == DISPLAY_SWITCH_ON) {
        display_set_field(data, UI_FIELD_FAN, "FAN ON", UI_COLOR_TEXT, UI_COLOR_BG);
    }
    else if (status->fan == DISPLAY_SWITCH_OFF) {
        display_set_field(data, UI_FIELD_FAN, "FAN OFF", UI_COLOR_DIM, UI_COLOR_BG);
    }
    else {
        display_set_field(data, UI_FIELD_FAN, "FAN --", UI_COLOR_DIM, UI_COLOR_BG);
    }

    /* ports */
    display_set_switch_badge(data, UI_FIELD_CHARGE, "CHARGE", status->charge);
    display_set_switch_badge(data, UI_FIELD_AC, "AC", status->ac);
    display_set_switch_badge(data, UI_FIELD_USB_A, "USB-A", status->usb_a);
    display_set_switch_badge(data, UI_FIELD_USB_C, "USB-C", status->usb_c);

    /* active fault */
    if (status->fault_code == FEE_CODE_DEFAULT) {
        display_set_field(data, UI_FIELD_ACTIVE_FAULT, "ACTIVE: NONE", UI_COLOR_DIM, UI_COLOR_BG);
    }
    else {
        snprintf(text, sizeof(text), "ACTIVE: E%u", (unsigned int)status->fault_code);
        display_set_field(data, UI_FIELD_ACTIVE_FAULT, text,
                          display_level_color(psu_event_log_fault_level(status->fault_code)), UI_COLOR_BG);
    }

    /* FPGA fault, "--" while its heartbeat is missing (pins mean nothing then) */
    if (!status->fpga_alive) {
        display_set_field(data, UI_FIELD_FPGA_FAULT, "FPGA: --", UI_COLOR_DIM, UI_COLOR_BG);
    }
    else if (status->fpga_fault_code == FEE_CODE_DEFAULT) {
        display_set_field(data, UI_FIELD_FPGA_FAULT, "FPGA: NONE", UI_COLOR_DIM, UI_COLOR_BG);
    }
    else {
        snprintf(text, sizeof(text), "FPGA: E%u", (unsigned int)status->fpga_fault_code);
        fg = display_level_color(psu_event_log_fault_level(status->fpga_fault_code));
        display_set_field(data, UI_FIELD_FPGA_FAULT, text, fg, UI_COLOR_BG);
    }
}

/**
 * @brief Refresh the event log rows, newest first, a placeholder line when empty.
 * @param[in,out] data Display data.
 * @param log          Event log.
 */
static void display_log_texts(psu_display_data_t *data, const psu_event_log_t *log)
{
    char     text[UI_TEXT_LEN];
    uint8_t  row;
    uint32_t seconds;
    /* event struct from psu_event_log.h */
    const psu_event_t *event;

    for (row = 0; row < UI_LOG_ROWS; row++) {
        event = psu_event_log_get(log, row);

        if (event != NULL) {
            seconds = event->time_ms / 1000UL;
            snprintf(text, sizeof(text), "%02lu:%02lu:%02lu %s",
                     (unsigned long)((seconds / 3600UL) % 100UL),
                     (unsigned long)((seconds / 60UL) % 60UL),
                     (unsigned long)(seconds % 60UL),
                     event->text);
            display_set_field(data, (psu_ui_field_t)(UI_FIELD_LOG_0 + row), text,
                              display_level_color(event->level), UI_COLOR_BG);
        }
        else if (row == 0) {
            display_set_field(data, UI_FIELD_LOG_0, "Events appear here",
                              display_level_color(EVENT_LEVEL_INFO), UI_COLOR_BG);
        }
        else {
            display_set_field(data, (psu_ui_field_t)(UI_FIELD_LOG_0 + row), "", UI_COLOR_DIM, UI_COLOR_BG);
        }
    }
}

/**
 * @brief Set the starting status: ports and fan off, everything else unknown.
 * @param[out] status System status.
 */
void psu_display_status_init(psu_display_status_t *status)
{
    status->state           = FSM_STATE_OFF;
    status->fault_code      = FEE_CODE_DEFAULT;
    status->fpga_alive      = false;
    status->fpga_fault_code = FEE_CODE_DEFAULT;
    status->battery_percent = -1;
    status->wifi_level      = -1;
    status->charge          = DISPLAY_SWITCH_OFF;
    status->ac              = DISPLAY_SWITCH_OFF;
    status->usb_a           = DISPLAY_SWITCH_OFF;
    status->usb_c           = DISPLAY_SWITCH_OFF;
    status->fan             = DISPLAY_SWITCH_OFF;
}

/**
 * @brief Start with every value marked unavailable.
 * @param[out] data Display data.
 */
void psu_display_init(psu_display_data_t *data)
{
    uint8_t field;

    data->temperature     = 0;
    data->voltage_mv      = 0;
    data->current_ma      = 0;
    data->power_mw        = 0;
    data->temperature_ok  = false;
    data->power_ok        = false;
    data->temperature_ms  = 0;
    data->power_ms        = 0;
    data->refresh_ms      = 0;
    data->battery_percent = -1;
    data->wifi_level      = -1;

    for (field = 0; field < UI_FIELD_COUNT; field++) {
        display_set_field(data, (psu_ui_field_t)field, "", UI_COLOR_TEXT, UI_COLOR_BG);
    }

    /* "--" until the first readings, other fields are filled by every update */
    display_measurement_texts(data);
}

/**
 * @brief Take the latest readings and status, refresh values and texts.
 * @param[in,out] data  Display data.
 * @param power         Latest power reading.
 * @param temperature   Latest temperature reading.
 * @param status        System status.
 * @param log           Event log.
 */
void psu_display_update(psu_display_data_t *data,
                        const psu_power_reading_t *power,
                        const psu_temperature_reading_t *temperature,
                        const psu_display_status_t *status,
                        const psu_event_log_t *log)
{
    uint32_t now_ms = millis();

    /* voltage, current, power */
    if (power->valid) {
        data->voltage_mv = power->voltage_mv;
        data->current_ma = power->current_ma;
        data->power_mw   = power->power_mw;
        data->power_ok   = true;
        data->power_ms   = now_ms;
    }
    else if (power->error || (uint32_t)(now_ms - data->power_ms) >= DISPLAY_POWER_STALE_MS) {
        data->power_ok = false;
    }

    /* temperature */
    if (temperature->valid) {
        data->temperature    = temperature->temperature;
        data->temperature_ok = true;
        data->temperature_ms = now_ms;
    }
    else if (temperature->error || (uint32_t)(now_ms - data->temperature_ms) >= DISPLAY_TEMPERATURE_STALE_MS) {
        data->temperature_ok = false;
    }

    /* measurements change every read, limit their redraws */
    if ((uint32_t)(now_ms - data->refresh_ms) >= DISPLAY_REFRESH_MS) {
        data->refresh_ms = now_ms;
        display_measurement_texts(data);
    }

    display_status_texts(data, status);
    display_log_texts(data, log);
}

/* ==================== UI RENDERER ==================== */

/* text, colors and validity of what is on screen now, per field */
static char     g_shown_text[UI_FIELD_COUNT][UI_TEXT_LEN];
static uint16_t g_shown_fg[UI_FIELD_COUNT];
static uint16_t g_shown_bg[UI_FIELD_COUNT];
static bool     g_shown_valid[UI_FIELD_COUNT];

/**
 * @brief Draw a text left aligned, padded with spaces to the element width.
 * @param e    Layout element.
 * @param text Text to draw.
 * @param fg   Text color.
 * @param bg   Background color, drawn behind every char so no clear is needed.
 */
static void display_draw_value(const psu_ui_element_t *e, const char *text, uint16_t fg, uint16_t bg)
{
    char   line[UI_TEXT_LEN];
    size_t chars;
    size_t i;

    chars = (size_t)e->w / (6U * (size_t)e->text_size);
    if (chars > UI_TEXT_LEN - 1U) {
        chars = UI_TEXT_LEN - 1U;
    }

    /* copy, cut and pad */
    for (i = 0; i < chars && text[i] != '\0'; i++) {
        line[i] = text[i];
    }
    for (; i < chars; i++) {
        line[i] = ' ';
    }
    line[chars] = '\0';

    g_tft.setTextSize((uint8_t)e->text_size);
    g_tft.setTextColor((uint16_t)fg, (uint16_t)bg);
    g_tft.setCursor((int16_t)e->x, (int16_t)e->y);
    g_tft.print(line);
}

/**
 * @brief Draw a text centered on a filled box.
 * @param e    Layout element.
 * @param text Text to draw, cut to the box width.
 * @param fg   Text color.
 * @param bg   Box color.
 */
static void display_draw_badge(const psu_ui_element_t *e, const char *text, uint16_t fg, uint16_t bg)
{
    char    line[UI_TEXT_LEN];
    size_t  chars;
    size_t  len;
    int16_t char_w = (int16_t)(6 * e->text_size);
    int16_t char_h = (int16_t)(8 * e->text_size);

    chars = (size_t)(e->w / char_w);
    snprintf(line, sizeof(line), "%s", text);
    len = strlen(line);
    if (len > chars) {
        len = chars;
        line[len] = '\0';
    }

    g_tft.fillRect((int16_t)e->x, (int16_t)e->y, (int16_t)e->w, (int16_t)e->h, (uint16_t)bg);
    g_tft.setTextSize((uint8_t)e->text_size);
    g_tft.setTextColor((uint16_t)fg, (uint16_t)bg);
    g_tft.setCursor((int16_t)(e->x + (e->w - (int16_t)len * char_w) / 2),
                    (int16_t)(e->y + (e->h - char_h) / 2));
    g_tft.print(line);
}

/**
 * @brief Draw the battery outline and its fill level, outline only when unknown.
 * @param e       Layout element, w includes the 3 px tip.
 * @param percent Battery level 0 to 100, -1 = unknown.
 */
static void display_draw_battery_icon(const psu_ui_element_t *e, int8_t percent)
{
    int16_t  body_w  = (int16_t)(e->w - 3);
    int16_t  inner_w = (int16_t)(body_w - 4);
    int16_t  inner_h = (int16_t)(e->h - 4);
    int16_t  fill_w  = 0;
    uint16_t outline = (percent >= 0) ? e->color : (uint16_t)UI_COLOR_INACTIVE;

    if (percent >= 0) {
        fill_w = (int16_t)((int32_t)inner_w * percent / 100);
    }

    g_tft.drawRect((int16_t)e->x, (int16_t)e->y, body_w, (int16_t)e->h, outline);
    g_tft.fillRect((int16_t)(e->x + body_w), (int16_t)(e->y + 4), (int16_t)3, (int16_t)(e->h - 8), outline);
    g_tft.fillRect((int16_t)(e->x + 1), (int16_t)(e->y + 1), (int16_t)(body_w - 2), (int16_t)(e->h - 2),
                   (uint16_t)UI_COLOR_BG);
    if (fill_w > 0) {
        g_tft.fillRect((int16_t)(e->x + 2), (int16_t)(e->y + 2), fill_w, inner_h, e->color);
    }
}

/**
 * @brief Draw 3 signal bars, all gray when there is no Wi-Fi.
 * @param e     Layout element.
 * @param level Lit bars 0 to 3, -1 = no Wi-Fi.
 */
static void display_draw_wifi_icon(const psu_ui_element_t *e, int8_t level)
{
    int16_t i;
    int16_t bar_h;

    for (i = 0; i < 3; i++) {
        bar_h = (int16_t)(4 + 5 * i);
        g_tft.fillRect((int16_t)(e->x + 2 + 7 * i), (int16_t)(e->y + e->h - bar_h), (int16_t)4, bar_h,
                       (uint16_t)((i < level) ? UI_COLOR_ACCENT : UI_COLOR_INACTIVE));
    }
}

/**
 * @brief Clear the screen, draw frames, separators and labels, mark live fields for redraw.
 */
void psu_display_ui_draw_static(void)
{
    uint16_t i;
    /* layout element struct from psu_ui_layout.h */
    const psu_ui_element_t *e;

    g_tft.setTextWrap(false);
    g_tft.fillRect((int16_t)0, (int16_t)0, g_display_width, g_display_height, (uint16_t)UI_COLOR_BG);

    for (i = 0; i < g_ui_layout_count; i++) {
        e = &g_ui_layout[i];
        if (e->type == UI_FRAME) {
            g_tft.drawRect((int16_t)e->x, (int16_t)e->y, (int16_t)e->w, (int16_t)e->h, (uint16_t)e->color);
        }
        else if (e->type == UI_FILL) {
            g_tft.fillRect((int16_t)e->x, (int16_t)e->y, (int16_t)e->w, (int16_t)e->h, (uint16_t)e->color);
        }
        else if (e->type == UI_LABEL && e->text != NULL) {
            g_tft.setTextSize((uint8_t)e->text_size);
            g_tft.setTextColor((uint16_t)e->color, (uint16_t)UI_COLOR_BG);
            g_tft.setCursor((int16_t)e->x, (int16_t)e->y);
            g_tft.print(e->text);
        }
    }

    for (i = 0; i < UI_FIELD_COUNT; i++) {
        g_shown_valid[i] = false;
    }
}

/**
 * @brief Redraw the next live element whose text or colors changed, at most one per call.
 * @param data Display data.
 * @return true if an element was drawn.
 */
bool psu_display_ui_draw_next(const psu_display_data_t *data)
{
    uint16_t i;
    /* layout element struct from psu_ui_layout.h */
    const psu_ui_element_t *e;
    /* field enum from psu_ui_layout.h */
    psu_ui_field_t f;

    for (i = 0; i < g_ui_layout_count; i++) {
        e = &g_ui_layout[i];
        f = e->field;

        if (f == UI_FIELD_NONE || f >= UI_FIELD_COUNT) {
            continue;
        }
        if (g_shown_valid[f] &&
            g_shown_fg[f] == data->fg[f] &&
            g_shown_bg[f] == data->bg[f] &&
            strcmp(g_shown_text[f], data->text[f]) == 0) {
            continue;
        }

        switch (e->type) {
        case UI_VALUE:        display_draw_value(e, data->text[f], data->fg[f], data->bg[f]); break;
        case UI_BADGE:        display_draw_badge(e, data->text[f], data->fg[f], data->bg[f]); break;
        case UI_BATTERY_ICON: display_draw_battery_icon(e, data->battery_percent);            break;
        case UI_WIFI_ICON:    display_draw_wifi_icon(e, data->wifi_level);                    break;
        default:                                                                              break;
        }

        snprintf(g_shown_text[f], UI_TEXT_LEN, "%s", data->text[f]);
        g_shown_fg[f]    = data->fg[f];
        g_shown_bg[f]    = data->bg[f];
        g_shown_valid[f] = true;
        return true;
    }

    return false;
}
