#ifndef SCOPE_HW_H
#define SCOPE_HW_H
#include <stdint.h>
#define SCOPE_BASE 0x40000000u
#define DMA_BASE 0x40400000u
#define DMA_BUFFER 0x10000000u
#define DMA_BUFFER_BYTES 0x00200000u
#define SEG_BUFFER 0x10400000u
#define SEGMENTS 8
enum {
    R_ID = 0,
    R_VER = 4,
    R_CTRL = 8,
    R_MODE = 12,
    R_RATE = 16,
    R_SAMPLES = 20,
    R_OTR = 28,
    R_TRIG = 32,
    R_STATE = 36,
    R_START = 40,
    R_TIME = 44,
    R_DEAD = 52,
    R_FRAME = 56,
    R_KEY = 60,
    R_ERRORS = 64,
    R_DROP = 68,
    R_DMA_BYTES = 72,
    R_DMA_LEN = 76,
    R_DMA_START = 80,
    R_DMA_ACCEPT = 84,
    R_DMA_FLAGS = 88,
    R_COMMIT = 92,
    R_DISPLAY = 96,
    R_OWNER = 100,
    R_RELEASE = 108,
    R_CRC = 112,
    R_HITS = 116,
    R_HDROP = 120,
    R_HWM = 124
};
#ifdef SCOPE_HOST_TEST
uint32_t scope_host_read(unsigned a);
void scope_host_write(unsigned a, uint32_t v);
#define scope_read scope_host_read
#define scope_write scope_host_write
#else
static inline uint32_t scope_read(unsigned a) {
    return *(volatile uint32_t *)(uintptr_t)(SCOPE_BASE + a);
}
static inline void scope_write(unsigned a, uint32_t v) {
    *(volatile uint32_t *)(uintptr_t)(SCOPE_BASE + a) = v;
    __asm__ volatile("dmb sy" ::: "memory");
}
#endif
#endif
