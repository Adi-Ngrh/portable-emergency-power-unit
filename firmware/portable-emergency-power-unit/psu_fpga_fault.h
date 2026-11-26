#ifndef PSU_FPGA_FAULT_H
#define PSU_FPGA_FAULT_H

#include "psu_fee.h"

#ifdef __cplusplus
extern "C" {
#endif

void           psu_fpga_fault_init(void);
psu_fee_code_t psu_fpga_fault_update(void);

#ifdef __cplusplus
}
#endif

#endif
