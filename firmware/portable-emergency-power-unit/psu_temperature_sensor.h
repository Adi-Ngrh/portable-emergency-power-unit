#ifndef PSU_TEMPERATURE_SENSOR_H
#define PSU_TEMPERATURE_SENSOR_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* temperature reading from the DS18B20 */
typedef struct
{
    int16_t temperature;  /* 1 LSB = 1/16 degC */
    bool    valid;        /* new reading this update */
    bool    error;        /* sensor failed on the last reading */
} psu_temperature_reading_t;

bool psu_temperature_sensor_init(void);
void psu_temperature_read(psu_temperature_reading_t *reading);

#ifdef __cplusplus
}
#endif

#endif
