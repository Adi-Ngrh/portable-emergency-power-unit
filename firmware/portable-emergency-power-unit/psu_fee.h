#ifndef PSU_FEE_H
#define PSU_FEE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* fault code, same as fee.sv */
typedef enum
{
    FEE_CODE_DEFAULT               = 0x0,
    FEE_CODE_OVERCURRENT           = 0x1,
    FEE_CODE_OVERVOLTAGE           = 0x2,
    FEE_CODE_OVERTEMPERATURE       = 0x3,
    FEE_CODE_SENSOR_FAILURE        = 0x4,
    FEE_CODE_UNDERVOLTAGE          = 0x5,
    FEE_CODE_FAN_FAILURE           = 0x6,
    FEE_CODE_COMMUNICATION_TIMEOUT = 0x7
} psu_fee_code_t;

/* buzzer pattern, same as fee.sv */
typedef enum
{
    FEE_PATTERN_DEFAULT  = 0x0,
    FEE_PATTERN_WARNING  = 0x1,
    FEE_PATTERN_SHUTDOWN = 0x2,
    FEE_PATTERN_CRITICAL = 0x3
} psu_fee_pattern_t;

/* FEE inputs */
typedef struct
{
    int32_t voltage_mv;             /* INA226 bus voltage = battery voltage, mV */
    int32_t current_ma;             /* INA226 current, mA, sign depends on direction */
    bool    power_valid;            /* new voltage/current reading this update */
    int16_t temperature;            /* 1 LSB = 1/16 degC */
    bool    temperature_valid;      /* new reading this update */
    bool    temperature_error;      /* temperature reader problem */
    bool    fan_failure;
    bool    sensor_failure;
    bool    communication_timeout;
    bool    critical_clear;         /* always false: no retry out of CRITICAL */
} psu_fee_inputs_t;

/* FEE outputs */
typedef struct
{
    bool              shutdown_response;
    bool              warning_response;
    bool              critical_response;  /* latched until critical_clear */
    psu_fee_code_t    fault_code;
    psu_fee_pattern_t buzzer_pattern;
} psu_fee_outputs_t;

/* debounce tracker for one signal */
typedef struct
{
    bool     active;    /* signal high on last update */
    uint32_t start_ms;  /* time signal went high */
    bool     valid;     /* high for the whole window */
} psu_fee_debounce_t;

/* FEE state */
typedef struct
{
    psu_fee_debounce_t fan_failure;
    psu_fee_debounce_t sensor_failure;
    psu_fee_debounce_t communication_timeout;

    bool               overvoltage_over_limit;      /* comparator result */
    uint8_t            overvoltage_count;           /* consecutive readings over the limit */
    bool               overvoltage_valid;           /* overvoltage confirmed */

    bool               undervoltage_under_limit;    /* comparator result */
    uint8_t            undervoltage_count;          /* consecutive readings under the limit */
    bool               undervoltage_valid;          /* undervoltage confirmed */

    bool               overcurrent_over_limit;      /* comparator result */
    uint8_t            overcurrent_count;           /* consecutive readings over the limit */
    bool               overcurrent_valid;           /* overcurrent confirmed */

    bool               overtemperature_over_limit;  /* comparator result */
    uint8_t            overtemperature_count;       /* consecutive hot readings */
    bool               overtemperature_valid;       /* overtemperature confirmed */

    psu_fee_outputs_t  out;
} psu_fee_t;

void psu_fee_init(psu_fee_t *fee);
void psu_fee_update(psu_fee_t *fee, const psu_fee_inputs_t *in);

#ifdef __cplusplus
}
#endif

#endif
