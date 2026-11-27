#ifndef PSU_BOARD_H
#define PSU_BOARD_H

#include <stdbool.h>

/* ==================== PINS ==================== */

#define SDA_PIN         21     /* I2C SDA */
#define SCL_PIN         22     /* I2C SCL */
#define DS18B20_PIN     4      /* OneWire bus, 1 sensor */
#define DS18B20_INSTALLED 0    /* 0 = not soldered yet, its boot check and reads are skipped; set 1 once soldered */
#define MAIN_RELAY_PIN  25     /* main relay: rocker switch - relay - inverter, charging module and load */
#define MAIN_RELAY_CLOSED_LEVEL  HIGH   /* pin level that closes the relay, swap both lines for a module that switches on LOW */
#define MAIN_RELAY_OPEN_LEVEL    LOW    /* pin level that opens the relay */
#define FAN_PIN         26     /* 12 V fan MOSFET */

/* ==================== TFT (MSP2807, ILI9341) ==================== */

#define TFT_SCK_PIN     33     /* SCK, routed through the GPIO matrix (easier to solder than GPIO18) */
#define TFT_MOSI_PIN    14     /* MOSI, module SDI (GPIO23 is used elsewhere) */
#define TFT_MISO_PIN    -1     /* not connected, the firmware never reads the display */
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
#define BOOT_SUCCESS_PIN     2 /* output to FPGA boot_success, also lights the on-board LED */
#define SHUTDOWN_SUCCESS_PIN 15 /* output to FPGA shutdown_success */

/* ==================== I2C BUS ==================== */

#define I2C_CLOCK_HZ    100000UL   /* 100 kHz */
#define INA226_ADDR     0x40       /* A0 and A1 tied to GND */

#ifdef __cplusplus
extern "C" {
#endif

bool psu_board_init(void);
void psu_main_relay_init(void);
void psu_main_relay_update(bool closed);

#ifdef __cplusplus
}
#endif

#endif
