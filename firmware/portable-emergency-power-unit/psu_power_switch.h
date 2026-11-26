#ifndef PSU_POWER_SWITCH_H
#define PSU_POWER_SWITCH_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

void psu_power_switch_init(void);
bool psu_power_switch_update(void);

#ifdef __cplusplus
}
#endif

#endif
