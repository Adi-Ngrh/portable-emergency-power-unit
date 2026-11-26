#ifndef PSU_MCU_HEARTBEAT_H
#define PSU_MCU_HEARTBEAT_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

void psu_mcu_heartbeat_init(void);
void psu_mcu_heartbeat_update(bool level);

#ifdef __cplusplus
}
#endif

#endif
