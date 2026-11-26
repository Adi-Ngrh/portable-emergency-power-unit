#include "psu_battery.h"

/* battery voltage range, 4 cells */
#define BATTERY_FULL_MV   13500L   /* shown as 100%, above is still 100% */
#define BATTERY_EMPTY_MV  11600L   /* shown as 0%, 4 cells x 2.9 V */

/**
 * @brief Battery level from the battery voltage, a straight line from empty to full.
 * @param voltage_mv Battery voltage in mV (INA226 bus voltage).
 * @return Battery level 0 to 100 (%).
 */
int8_t psu_battery_percent(int32_t voltage_mv)
{
    int32_t range_mv = BATTERY_FULL_MV - BATTERY_EMPTY_MV;
    int32_t above_empty_mv;
    int32_t percent;

    /* outside the range: limit to 0% or 100% */
    if (voltage_mv <= BATTERY_EMPTY_MV) {
        return 0;
    }
    if (voltage_mv >= BATTERY_FULL_MV) {
        return 100;
    }

    /* position inside the range, rounded to the nearest percent */
    above_empty_mv = voltage_mv - BATTERY_EMPTY_MV;
    percent        = (above_empty_mv * 100L + range_mv / 2L) / range_mv;

    return (int8_t)percent;
}
