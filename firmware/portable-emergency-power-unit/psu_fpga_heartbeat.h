#ifndef PSU_FPGA_HEARTBEAT_H
#define PSU_FPGA_HEARTBEAT_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

void psu_fpga_heartbeat_init(void);
bool psu_fpga_heartbeat_update(void);

#ifdef __cplusplus
}
#endif

#endif
