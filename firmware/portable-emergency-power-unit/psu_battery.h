#ifndef PSU_BATTERY_H
#define PSU_BATTERY_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int8_t psu_battery_percent(int32_t voltage_mv);

#ifdef __cplusplus
}
#endif

#endif
