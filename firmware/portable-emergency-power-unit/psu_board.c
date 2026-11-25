#include "psu_board.h"
#include "psu_power_sensor.h"
#include "psu_temperature_sensor.h"

/**
 * @brief Initialize the main system board (sensors only for now).
 * @return true if every sensor responds.
 */
bool psu_board_init(void)
{
    bool ok = true;

    /* power sensor (also starts the I2C bus) */
    if (!psu_power_sensor_init()) {
        ok = false;
    }

    /* temperature sensors */
    if (!psu_temperature_sensor_init()) {
        ok = false;
    }

    return ok;
}
