#ifndef PSU_MCU_STATUS_H
#define PSU_MCU_STATUS_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

void psu_mcu_status_init(void);
void psu_mcu_status_update(bool boot_success, bool shutdown_success);

#ifdef __cplusplus
}
#endif

#endif
