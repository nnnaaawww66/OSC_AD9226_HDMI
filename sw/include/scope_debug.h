#ifndef SCOPE_DEBUG_H
#define SCOPE_DEBUG_H
#include <stdint.h>
/* Reserved last 4KiB of low OCM. AP0 physical accesses work while CPU runs. */
#define SCOPE_DEBUG_ADDRESS 0x0002f000u
#define SCOPE_DEBUG_MAGIC 0x53434a54u
typedef struct {
    uint32_t magic, abi, stage, heartbeat, request, done, flags, length;
    char command[160];
    char response[2048];
} scope_debug_mailbox;
#ifdef SCOPE_HOST_TEST
static volatile scope_debug_mailbox host_debug_mailbox;
#define DEBUG_MAILBOX (&host_debug_mailbox)
#else
#include "xil_mmu.h"
#define DEBUG_MAILBOX ((volatile scope_debug_mailbox *)(uintptr_t)SCOPE_DEBUG_ADDRESS)
#endif
static void debug_barrier(void) {
#ifndef SCOPE_HOST_TEST
    __asm__ volatile("dmb sy" ::: "memory");
#endif
}
static void debug_init(void) {
#ifndef SCOPE_HOST_TEST
    Xil_SetTlbAttributes(0, NORM_NONCACHE);
#endif
    volatile scope_debug_mailbox *m = DEBUG_MAILBOX;
    m->magic = 0;
    m->abi = 1;
    m->stage = 1;
    m->heartbeat = 0;
    m->request = 0;
    m->done = 0;
    m->flags = 0;
    m->length = 0;
    m->command[0] = 0;
    m->response[0] = 0;
    debug_barrier();
    m->magic = SCOPE_DEBUG_MAGIC;
}
#endif
