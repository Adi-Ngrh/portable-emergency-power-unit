#ifndef PSU_BOARD_H
#define PSU_BOARD_H

#include <stdbool.h>

/* ==================== PINS ==================== */

#define SDA_PIN         21     /* I2C SDA */
#define SCL_PIN         22     /* I2C SCL */
#define DS18B20_PIN     4      /* OneWire bus, 2 sensors in parallel */
#define RELAY_A_PIN     25     /* charge path: grid - charger - relay A - battery */
#define RELAY_B_PIN     27     /* discharge path: BMS - relay B - inverter & USB-C */
#define FAN_PIN         26     /* 12 V fan MOSFET */

/* ==================== TFT (MSP2807, ILI9341) ==================== */

#define TFT_SCK_PIN     18     /* VSPI SCK */
#define TFT_MOSI_PIN    23     /* VSPI MOSI, module SDI */
#define TFT_MISO_PIN    19     /* VSPI MISO, module SDO, not read by the firmware */
#define TFT_CS_PIN      5      /* VSPI SS */
#define TFT_DC_PIN      16
#define TFT_RST_PIN     17
#define TFT_LED_PIN     32     /* backlight, high = on */

/* ==================== I2C BUS ==================== */

#define I2C_CLOCK_HZ    100000UL   /* 100 kHz */
#define INA226_ADDR     0x40       /* A0 and A1 tied to GND */

/* ==================== FITTED PARTS ==================== */

#define DS18B20_COUNT      2        /* sensors on the OneWire bus */

#ifdef __cplusplus
extern "C" {
#endif

bool psu_board_init(void);

#ifdef __cplusplus
}
#endif

#endif
