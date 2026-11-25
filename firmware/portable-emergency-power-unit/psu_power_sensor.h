#ifndef PSU_POWER_SENSOR_H
#define PSU_POWER_SENSOR_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* power reading from the INA226 */
typedef struct
{
    int32_t voltage_mv;  /* bus voltage, mV */
    int32_t current_ma;  /* shunt current, mA, sign set by shunt orientation */
    int32_t power_mw;    /* power, mW */
    bool    valid;       /* new reading this update */
    bool    error;       /* last read failed */
} psu_power_reading_t;

bool psu_power_sensor_init(void);
void psu_power_read(psu_power_reading_t *reading);

#ifdef __cplusplus
}
#endif

#endif
