/*
 * Arduino core functions used:
 *   millis()
 */

#include <Arduino.h>
#include "psu_fee.h"

/* ==================== FAULT LIMITS (tweak here, keep equal to fee.sv) ==================== */

/* battery voltage, LiFePO4 4 cells: 13.5 V full at rest, up to 14.6 V while charging, 11.6 V empty */
#define FEE_OVERVOLTAGE_SET_MV      14800L  /* trip at or above (mV), above the 14.6 V charging voltage */
#define FEE_OVERVOLTAGE_CLEAR_MV    14400L  /* release below (mV) */
#define FEE_UNDERVOLTAGE_SET_MV     11600L  /* trip at or below (mV), battery empty (4 x 2.9 V) */
#define FEE_UNDERVOLTAGE_CLEAR_MV   12000L  /* release above (mV) */

/* current, checked in both directions (charging and discharging) */
#define FEE_OVERCURRENT_SET_MA      20000L  /* trip at or above (mA), GUESS: confirm with the team */
#define FEE_OVERCURRENT_CLEAR_MA    18000L  /* release below (mA) */

/* readings beyond a voltage/current limit needed to trip (one reading every ~40 ms) */
#define FEE_POWER_READING_COUNT     3U

/* overtemperature (1 LSB = 1/16 degC) */
#define FEE_OVERTEMP_SET_C          60   /* trip at or above (degC) */
#define FEE_OVERTEMP_CLEAR_C        55   /* release below (degC) */
#define FEE_OVERTEMP_READING_COUNT  3U   /* readings needed to trip */

/* ==================== OTHER SETTINGS ==================== */

/* debounce windows */
#define FEE_FAN_FAILURE_DEBOUNCE_MS            10UL
#define FEE_SENSOR_FAILURE_DEBOUNCE_MS         1UL
#define FEE_COMMUNICATION_TIMEOUT_DEBOUNCE_MS  30UL

/* overtemperature limits in sensor format */
#define FEE_OVERTEMP_SET_LEVEL      ((int16_t)(FEE_OVERTEMP_SET_C * 16))
#define FEE_OVERTEMP_CLEAR_LEVEL    ((int16_t)(FEE_OVERTEMP_CLEAR_C * 16))

/**
 * @brief Clear a debounce tracker.
 * @param d Debounce tracker.
 */
static void fee_debounce_reset(psu_fee_debounce_t *d)
{
    d->active   = false;
    d->start_ms = 0;
    d->valid    = false;
}

/**
 * @brief Debounce one fault signal.
 * @param d         Debounce tracker.
 * @param raw       Current signal level.
 * @param now_ms    Current time in ms.
 * @param window_ms Time the signal must stay high.
 * @return true once the signal has stayed high for window_ms.
 */
static bool fee_debounce_update(psu_fee_debounce_t *d, bool raw, uint32_t now_ms, uint32_t window_ms)
{
    if (!raw) {
        d->active = false;
        d->valid  = false;
        return false;
    }

    if (!d->active) {
        d->active   = true;
        d->start_ms = now_ms;
    }

    /* wrap-safe elapsed time */
    if ((uint32_t)(now_ms - d->start_ms) >= window_ms) {
        d->valid = true;
    }

    return d->valid;
}

/**
 * @brief Pick fault code and buzzer pattern from the highest active fault.
 * @param fee FEE instance.
 */
static void fee_priority_encoder(psu_fee_t *fee)
{
    if (fee->overcurrent_valid) {
        fee->out.fault_code     = FEE_CODE_OVERCURRENT;
        fee->out.buzzer_pattern = FEE_PATTERN_CRITICAL;
    }
    else if (fee->overvoltage_valid) {
        fee->out.fault_code     = FEE_CODE_OVERVOLTAGE;
        fee->out.buzzer_pattern = FEE_PATTERN_CRITICAL;
    }
    else if (fee->overtemperature_valid) {
        fee->out.fault_code     = FEE_CODE_OVERTEMPERATURE;
        fee->out.buzzer_pattern = FEE_PATTERN_SHUTDOWN;
    }
    else if (fee->sensor_failure.valid) {
        fee->out.fault_code     = FEE_CODE_SENSOR_FAILURE;
        fee->out.buzzer_pattern = FEE_PATTERN_SHUTDOWN;
    }
    else if (fee->undervoltage_valid) {
        fee->out.fault_code     = FEE_CODE_UNDERVOLTAGE;
        fee->out.buzzer_pattern = FEE_PATTERN_WARNING;
    }
    else if (fee->fan_failure.valid) {
        fee->out.fault_code     = FEE_CODE_FAN_FAILURE;
        fee->out.buzzer_pattern = FEE_PATTERN_WARNING;
    }
    else if (fee->communication_timeout.valid) {
        fee->out.fault_code     = FEE_CODE_COMMUNICATION_TIMEOUT;
        fee->out.buzzer_pattern = FEE_PATTERN_WARNING;
    }
    else {
        fee->out.fault_code     = FEE_CODE_DEFAULT;
        fee->out.buzzer_pattern = FEE_PATTERN_DEFAULT;
    }
}

/**
 * @brief Reset the FEE, same as fee.sv reset.
 * @param fee FEE instance.
 */
void psu_fee_init(psu_fee_t *fee)
{
    fee_debounce_reset(&fee->fan_failure);
    fee_debounce_reset(&fee->sensor_failure);
    fee_debounce_reset(&fee->communication_timeout);

    fee->overvoltage_over_limit     = false;
    fee->overvoltage_count          = 0;
    fee->overvoltage_valid          = false;

    fee->undervoltage_under_limit   = false;
    fee->undervoltage_count         = 0;
    fee->undervoltage_valid         = false;

    fee->overcurrent_over_limit     = false;
    fee->overcurrent_count          = 0;
    fee->overcurrent_valid          = false;

    fee->overtemperature_over_limit = false;
    fee->overtemperature_count      = 0;
    fee->overtemperature_valid      = false;

    fee->out.shutdown_response = false;
    fee->out.warning_response  = false;
    fee->out.critical_response = false;
    fee->out.fault_code        = FEE_CODE_DEFAULT;
    fee->out.buzzer_pattern    = FEE_PATTERN_DEFAULT;
}

/**
 * @brief Run one FEE update: debounce, voltage, current, overtemperature, classify, encode, latch.
 * @param fee FEE instance.
 * @param in  FEE inputs.
 */
void psu_fee_update(psu_fee_t *fee, const psu_fee_inputs_t *in)
{
    uint32_t now_ms = millis();

    int32_t current_size;
    bool    fan_failure_valid;
    bool    sensor_failure_valid;
    bool    communication_timeout_valid;
    bool    critical_now;

    /* debounce */
    fan_failure_valid = fee_debounce_update(&fee->fan_failure, in->fan_failure,
                                            now_ms, FEE_FAN_FAILURE_DEBOUNCE_MS);
    sensor_failure_valid = fee_debounce_update(&fee->sensor_failure,
                                               in->sensor_failure || in->temperature_error,
                                               now_ms, FEE_SENSOR_FAILURE_DEBOUNCE_MS);
    communication_timeout_valid = fee_debounce_update(&fee->communication_timeout,
                                                      in->communication_timeout,
                                                      now_ms, FEE_COMMUNICATION_TIMEOUT_DEBOUNCE_MS);

    /* voltage and current: hysteresis, then N consecutive readings beyond the limit */
    if (in->power_valid) {
        /* overvoltage: trip at or above the set level, release below the clear level */
        if (in->voltage_mv >= FEE_OVERVOLTAGE_SET_MV) {
            fee->overvoltage_over_limit = true;
        }
        else if (in->voltage_mv < FEE_OVERVOLTAGE_CLEAR_MV) {
            fee->overvoltage_over_limit = false;
        }

        if (fee->overvoltage_over_limit) {
            if (fee->overvoltage_count < FEE_POWER_READING_COUNT) {
                fee->overvoltage_count++;
            }
        }
        else {
            fee->overvoltage_count = 0;
        }

        /* undervoltage: trip at or below the set level, release above the clear level */
        if (in->voltage_mv <= FEE_UNDERVOLTAGE_SET_MV) {
            fee->undervoltage_under_limit = true;
        }
        else if (in->voltage_mv > FEE_UNDERVOLTAGE_CLEAR_MV) {
            fee->undervoltage_under_limit = false;
        }

        if (fee->undervoltage_under_limit) {
            if (fee->undervoltage_count < FEE_POWER_READING_COUNT) {
                fee->undervoltage_count++;
            }
        }
        else {
            fee->undervoltage_count = 0;
        }

        /* overcurrent: the sign of the current depends on its direction, so use its size */
        current_size = in->current_ma;
        if (current_size < 0) {
            current_size = -current_size;
        }

        if (current_size >= FEE_OVERCURRENT_SET_MA) {
            fee->overcurrent_over_limit = true;
        }
        else if (current_size < FEE_OVERCURRENT_CLEAR_MA) {
            fee->overcurrent_over_limit = false;
        }

        if (fee->overcurrent_over_limit) {
            if (fee->overcurrent_count < FEE_POWER_READING_COUNT) {
                fee->overcurrent_count++;
            }
        }
        else {
            fee->overcurrent_count = 0;
        }
    }
    fee->overvoltage_valid  = (fee->overvoltage_count >= FEE_POWER_READING_COUNT);
    fee->undervoltage_valid = (fee->undervoltage_count >= FEE_POWER_READING_COUNT);
    fee->overcurrent_valid  = (fee->overcurrent_count >= FEE_POWER_READING_COUNT);

    /* overtemperature: hysteresis, then N consecutive hot readings */
    if (in->temperature_valid) {
        if (in->temperature >= FEE_OVERTEMP_SET_LEVEL) {
            fee->overtemperature_over_limit = true;
        }
        else if (in->temperature < FEE_OVERTEMP_CLEAR_LEVEL) {
            fee->overtemperature_over_limit = false;
        }

        if (fee->overtemperature_over_limit) {
            if (fee->overtemperature_count < FEE_OVERTEMP_READING_COUNT) {
                fee->overtemperature_count++;
            }
        }
        else {
            fee->overtemperature_count = 0;
        }
    }
    fee->overtemperature_valid = (fee->overtemperature_count >= FEE_OVERTEMP_READING_COUNT);

    /* fault classes */
    fee->out.warning_response  = fee->undervoltage_valid || fan_failure_valid || communication_timeout_valid;
    fee->out.shutdown_response = fee->overtemperature_valid || sensor_failure_valid;
    critical_now               = fee->overcurrent_valid || fee->overvoltage_valid;

    fee_priority_encoder(fee);

    /* critical latch, active fault wins over clear */
    if (critical_now) {
        fee->out.critical_response = true;
    }
    else if (in->critical_clear) {
        fee->out.critical_response = false;
    }
}
