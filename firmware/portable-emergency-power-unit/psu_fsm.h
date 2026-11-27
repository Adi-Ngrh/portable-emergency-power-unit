#ifndef PSU_FSM_H
#define PSU_FSM_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* states, same one-hot values as fsm.sv */
typedef enum
{
    FSM_STATE_OFF      = 0x01,
    FSM_STATE_BOOT     = 0x02,
    FSM_STATE_NORMAL   = 0x04,
    FSM_STATE_WARNING  = 0x08,
    FSM_STATE_CRITICAL = 0x10,
    FSM_STATE_SHUTDOWN = 0x20,
    FSM_STATE_RECOVERY = 0x40
} psu_fsm_state_t;

/* FSM inputs */
typedef struct
{
    bool boot_passed;        /* main system init passed */
    bool boot_failed;        /* main system init failed */
    bool shutdown_done;      /* main system shutdown finished */
    bool battery_low;
    bool battery_critical;
    bool warning_request;    /* from FEE */
    bool shutdown_request;   /* from FEE */
    bool critical_request;   /* from FEE */
    bool manual_shutdown;
    bool fpga_alive;         /* FPGA heartbeat seen in the last 3 s, MCU only */
} psu_fsm_inputs_t;

/* FSM outputs */
typedef struct
{
    bool system_enable;      /* main system on, for the relay code (not written yet) */
    bool boot_success;       /* to FPGA: main system is up */
    bool shutdown_success;   /* to FPGA: main system is off */
} psu_fsm_outputs_t;

/* FSM state */
typedef struct
{
    psu_fsm_state_t   state;
    bool              booted_once;          /* left OFF once since power-on, OFF is final after that */
    bool              battery_fault_latch;  /* shutdown caused by battery */
    psu_fsm_outputs_t out;
} psu_fsm_t;

void psu_fsm_init(psu_fsm_t *fsm);
void psu_fsm_update(psu_fsm_t *fsm, const psu_fsm_inputs_t *in);

#ifdef __cplusplus
}
#endif

#endif
