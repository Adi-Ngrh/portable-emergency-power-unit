#ifndef PSU_BOARD_H
#define PSU_BOARD_H

#include <stdbool.h>

/* ==================== PINS ==================== */

#define SDA_PIN         21     /* I2C SDA */
#define SCL_PIN         22     /* I2C SCL */
#define DS18B20_PIN     4      /* OneWire bus, 1 sensor */
#define RELAY_A_PIN     25     /* charge path: grid - charger - relay A - battery */
#define RELAY_B_PIN     27     /* discharge path: BMS - relay B - inverter & USB-C */
#define FAN_PIN         26     /* 12 V fan MOSFET */
#define POWER_SWITCH_PIN 33    /* rocker switch to manual_power, high = ON */

/* ==================== TFT (MSP2807, ILI9341) ==================== */

#define TFT_SCK_PIN     18     /* VSPI SCK */
#define TFT_MOSI_PIN    23     /* VSPI MOSI, module SDI */
#define TFT_MISO_PIN    19     /* VSPI MISO, module SDO, not read by the firmware */
#define TFT_CS_PIN      5      /* VSPI SS */
#define TFT_DC_PIN      16
#define TFT_RST_PIN     17
#define TFT_LED_PIN     32     /* backlight, high = on */

/* ==================== FPGA LINK ==================== */

#define MCU_HEARTBEAT_PIN   13 /* output to FPGA mcu_heartbeat, not a strapping pin (quiet at reset) */
#define FPGA_HEARTBEAT_PIN  34 /* input from FPGA fpga_heartbeat, input-only pin */
#define FPGA_FAULT_BIT0_PIN 35 /* input from FPGA fault_code_bus[0], input-only pin */
#define FPGA_FAULT_BIT1_PIN 36 /* input from FPGA fault_code_bus[1], input-only pin (VP) */
#define FPGA_FAULT_BIT2_PIN 39 /* input from FPGA fault_code_bus[2], input-only pin (VN) */

/* ==================== I2C BUS ==================== */

#define I2C_CLOCK_HZ    100000UL   /* 100 kHz */
#define INA226_ADDR     0x40       /* A0 and A1 tied to GND */

#ifdef __cplusplus
extern "C" {
#endif

bool psu_board_init(void);

#ifdef __cplusplus
}
#endif

#endif
