#ifndef PSU_EVENT_LOG_H
#define PSU_EVENT_LOG_H

#include <stdint.h>
#include <stdbool.h>
#include "psu_fsm.h"
#include "psu_fee.h"

#ifdef __cplusplus
extern "C" {
#endif

#define EVENT_LOG_SIZE      8    /* events kept in RAM, oldest is dropped */
#define EVENT_LOG_TEXT_LEN  32   /* longest text is "STATE SHUTDOWN -> RECOVERY" */

/* event class, decides the log color */
typedef enum
{
    EVENT_LEVEL_INFO,
    EVENT_LEVEL_CLEARED,
    EVENT_LEVEL_WARNING,
    EVENT_LEVEL_SHUTDOWN,
    EVENT_LEVEL_CRITICAL
} psu_event_level_t;

/* one logged event */
typedef struct
{
    uint32_t          time_ms;                   /* uptime when it happened */
    psu_event_level_t level;
    char              text[EVENT_LOG_TEXT_LEN];
} psu_event_t;

/* event log ring buffer */
typedef struct
{
    psu_event_t     entry[EVENT_LOG_SIZE];
    uint8_t         next;         /* slot for the next event */
    uint8_t         count;        /* stored events */
    psu_fsm_state_t last_state;   /* for change detection */
    psu_fee_code_t  last_fault;   /* for change detection */
} psu_event_log_t;

void               psu_event_log_init(psu_event_log_t *log);
void               psu_event_log_add(psu_event_log_t *log, uint32_t now_ms,
                                     psu_event_level_t level, const char *text);
void               psu_event_log_track(psu_event_log_t *log, uint32_t now_ms,
                                       psu_fsm_state_t state, psu_fee_code_t fault);
const psu_event_t *psu_event_log_get(const psu_event_log_t *log, uint8_t index);
const char        *psu_event_log_state_name(psu_fsm_state_t state);
const char        *psu_event_log_fault_name(psu_fee_code_t code);
psu_event_level_t  psu_event_log_fault_level(psu_fee_code_t code);

#ifdef __cplusplus
}
#endif

#endif
