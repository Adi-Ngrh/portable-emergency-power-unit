/*
 * Arduino core functions used:
 *   millis()
 */

#include <Arduino.h>
#include "psu_fee.h"

/* debounce windows */
#define FEE_OVERCURRENT_DEBOUNCE_MS            1UL   /* FPGA uses 1 us */
#define FEE_OVERVOLTAGE_DEBOUNCE_MS            1UL   /* FPGA uses 1 us */
#define FEE_UNDERVOLTAGE_DEBOUNCE_MS           1UL
#define FEE_FAN_FAILURE_DEBOUNCE_MS            10UL
#define FEE_SENSOR_FAILURE_DEBOUNCE_MS         1UL
#define FEE_COMMUNICATION_TIMEOUT_DEBOUNCE_MS  30UL

/* overtemperature (1 LSB = 1/16 degC) */
#define FEE_OVERTEMP_SET_C          60   /* trip at or above (degC) */
#define FEE_OVERTEMP_CLEAR_C        55   /* release below (degC) */
#define FEE_OVERTEMP_READING_COUNT  3U   /* readings needed to trip */
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
    if (fee->overcurrent.valid) {
        fee->out.fault_code     = FEE_CODE_OVERCURRENT;
        fee->out.buzzer_pattern = FEE_PATTERN_CRITICAL;
    }
    else if (fee->overvoltage.valid) {
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
    else if (fee->undervoltage.valid) {
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
    fee_debounce_reset(&fee->overcurrent);
    fee_debounce_reset(&fee->overvoltage);
    fee_debounce_reset(&fee->undervoltage);
    fee_debounce_reset(&fee->fan_failure);
    fee_debounce_reset(&fee->sensor_failure);
    fee_debounce_reset(&fee->communication_timeout);

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
 * @brief Run one FEE update: debounce, overtemperature, classify, encode, latch.
 * @param fee FEE instance.
 * @param in  FEE inputs.
 */
void psu_fee_update(psu_fee_t *fee, const psu_fee_inputs_t *in)
{
    uint32_t now_ms = millis();

    bool overcurrent_valid;
    bool overvoltage_valid;
    bool undervoltage_valid;
    bool fan_failure_valid;
    bool sensor_failure_valid;
    bool communication_timeout_valid;
    bool critical_now;

    /* debounce */
    overcurrent_valid = fee_debounce_update(&fee->overcurrent, in->overcurrent,
                                            now_ms, FEE_OVERCURRENT_DEBOUNCE_MS);
    overvoltage_valid = fee_debounce_update(&fee->overvoltage, in->overvoltage,
                                            now_ms, FEE_OVERVOLTAGE_DEBOUNCE_MS);
    undervoltage_valid = fee_debounce_update(&fee->undervoltage, in->undervoltage,
                                             now_ms, FEE_UNDERVOLTAGE_DEBOUNCE_MS);
    fan_failure_valid = fee_debounce_update(&fee->fan_failure, in->fan_failure,
                                            now_ms, FEE_FAN_FAILURE_DEBOUNCE_MS);
    sensor_failure_valid = fee_debounce_update(&fee->sensor_failure,
                                               in->sensor_failure || in->temperature_error,
                                               now_ms, FEE_SENSOR_FAILURE_DEBOUNCE_MS);
    communication_timeout_valid = fee_debounce_update(&fee->communication_timeout,
                                                      in->communication_timeout,
                                                      now_ms, FEE_COMMUNICATION_TIMEOUT_DEBOUNCE_MS);

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
    fee->out.warning_response  = undervoltage_valid || fan_failure_valid || communication_timeout_valid;
    fee->out.shutdown_response = fee->overtemperature_valid || sensor_failure_valid;
    critical_now               = overcurrent_valid || overvoltage_valid;

    fee_priority_encoder(fee);

    /* critical latch, active fault wins over clear */
    if (critical_now) {
        fee->out.critical_response = true;
    }
    else if (in->critical_clear) {
        fee->out.critical_response = false;
    }
}
