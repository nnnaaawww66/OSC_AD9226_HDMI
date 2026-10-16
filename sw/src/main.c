/* Z7-Lite scope firmware, SDK 2018.3 standalone. No flash writes. */
#include "xparameters.h"
#include "xil_cache.h"
#include "xil_exception.h"
#include "xscugic.h"
#include "xuartps_hw.h"
#include "xtime_l.h"
#include "sleep.h"
#include "scope_analysis.h"
#include "scope_hw.h"
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

enum { DSO, DPX, EYE, FFT, ROLL, MEM, SEG };
static const char *modes[] = {"DSO", "DPX", "EYE", "FFT", "ROLL", "MEM", "SEG"};
typedef struct {
    unsigned mode, run, sim, level, hyst, edge, trig, rate, fft_n, hann, bitrate, span, segment,
        offset, encoding, gain;
    double uv_per_code, zero;
} settings;
static settings cfg = {DSO, 1,       1,     2048, 8, 0, 0, 10000000, 4096,
                       1,   1000000, 16384, 0,    0, 0, 0, 0,        2048},
                saved;
static uint16_t record[SCOPE_N] __attribute__((aligned(64)));
static uint32_t wave[SCOPE_W];
static uint8_t hist[HIST_W * HIST_H];
static float re[4096], im[4096], spectrum[2048];
static char screen[7200], command[160];
static unsigned command_len, sequence, menu, selection;
static unsigned mem_gate, mem_valid, seg_count, last_record, valid_record, refreshes,
    captures_processed, hist_updates, key_lost, dirty = 1;
static uint32_t hits, drops;
static unsigned roll_sequence, roll_columns, roll_lost;
static uint64_t roll_time;
static unsigned mem_source_sim, segment_sim[SEGMENTS], raster_fault;
static uint64_t mem_first_index;
static uint64_t segment_time[SEGMENTS], first_index;
static unsigned segment_len[SEGMENTS];
static unsigned last_key_sequence;
static volatile unsigned key_head, key_tail;
static volatile uint32_t key_queue[16];
static volatile unsigned dma_irq, dma_errors;
static XScuGic gic;
static scope_measurements measurement;
static double fft_hz, fft_db, render_ms, frame_hz;
static uint64_t last_render, first_render;
static char message[90] = "SIM SELFTEST / ADC UNCALIBRATED / MEM & SEG LOCKED";
static unsigned qualified_rate_mask =
    1; /* G2 HIL evidence is required before higher rates are enabled. */
static uint64_t now(void) {
    XTime t;
    XTime_GetTime(&t);
    return t;
}
static double elapsed_ms(uint64_t t) { return (now() - t) * 1000.0 / COUNTS_PER_SECOND; }
static uint32_t dma_read(unsigned off) { return *(volatile uint32_t *)(uintptr_t)(DMA_BASE + off); }
static void dma_write(unsigned off, uint32_t value) {
    *(volatile uint32_t *)(uintptr_t)(DMA_BASE + off) = value;
#ifndef SCOPE_HOST_TEST
    __asm__ volatile("dmb sy" ::: "memory");
#endif
}
static void reply(int ok, const char *fmt, ...) {
    va_list ap;
    printf("%s seq=%u ", ok ? "OK" : "ERR", ++sequence);
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    printf("\r\n");
}
static int wait_idle(unsigned reg, unsigned mask, unsigned timeout) {
    uint64_t t = now();
    while (scope_read(reg) & mask) {
        if (elapsed_ms(t) > timeout)
            return 0;
    }
    return 1;
}
static void set_message(const char *s) {
    snprintf(message, sizeof(message), "%s", s);
    dirty = 1;
}
static int apply(void) {
    if (!wait_idle(R_STATE, 1u << 9, 50)) {
        set_message("CFG HANDSHAKE TIMEOUT");
        return 0;
    }
    scope_write(R_CTRL, (cfg.run ? 1 : 0) | (cfg.sim ? 2 : 0) | (cfg.edge ? 4 : 0) |
                            (cfg.trig << 3) | (cfg.encoding << 6) | (cfg.level << 8) |
                            (cfg.hyst << 20));
    scope_write(R_MODE, cfg.mode);
    if (cfg.run)
        valid_record = 0;
    last_record = scope_read(R_TRIG);
    dirty = 1;
    return 1;
}
static void key_isr(void *unused) {
    (void)unused;
    uint32_t e = scope_read(R_KEY);
    unsigned seq = e >> 16;
    if (last_key_sequence && ((seq - last_key_sequence) & 65535) > 1)
        key_lost += ((seq - last_key_sequence) & 65535) - 1;
    last_key_sequence = seq;
    unsigned next = (key_head + 1) & 15;
    if (next != key_tail) {
        key_queue[key_head] = e;
        key_head = next;
    } else
        key_lost++;
    scope_write(R_KEY, e);
}
static void dma_isr(void *unused) {
    (void)unused;
    uint32_t s = dma_read(0x34);
    dma_write(0x34, s & 0x7000);
    dma_irq = 1;
    if (s & 0x770)
        dma_errors = s;
}
static int interrupts_init(void) {
    XScuGic_Config *gc = XScuGic_LookupConfig(XPAR_SCUGIC_SINGLE_DEVICE_ID);
    if (!gc || XScuGic_CfgInitialize(&gic, gc, gc->CpuBaseAddress) != XST_SUCCESS)
        return 0;
    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                                 (Xil_ExceptionHandler)XScuGic_InterruptHandler, &gic);
    XScuGic_SetPriorityTriggerType(&gic, 61, 0xa0, 1);
    XScuGic_Connect(&gic, 61, key_isr, 0);
    XScuGic_Enable(&gic, 61);
    XScuGic_SetPriorityTriggerType(&gic, 62, 0x80, 1);
    XScuGic_Connect(&gic, 62, dma_isr, 0);
    XScuGic_Enable(&gic, 62);
    Xil_ExceptionEnable();
    return 1;
}
static void text(unsigned row, unsigned col, const char *fmt, ...) {
    char s[170];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(s, sizeof(s), fmt, ap);
    va_end(ap);
    unsigned i;
    for (i = 0; s[i] && col + i < 160 && row < 45; i++)
        screen[row * 160 + col + i] = s[i] >= 32 && s[i] < 127 ? s[i] : '?';
}
static const char *state_name(unsigned s) {
    switch ((s >> 1) & 7) {
    case 0:
        return "IDLE";
    case 1:
        return "PREFILL";
    case 2:
        return "ARMED";
    case 3:
        return "POST";
    case 4:
        return "HOLD";
    default:
        return "FAULT";
    }
}
static void draw_ui(void) {
    memset(screen, ' ', sizeof(screen));
    unsigned s = scope_read(R_STATE);
    unsigned visible_sim =
        (cfg.mode == MEM && mem_valid)
            ? mem_source_sim
            : (cfg.mode == SEG && segment_len[cfg.segment] ? segment_sim[cfg.segment] : cfg.sim);
    uint32_t err = scope_read(R_ERRORS);
    text(1, 3, "Z7 SCOPE  |  %-4s  |  %s  |  %s  |  %u MSa/s  |  %s", modes[cfg.mode],
         cfg.run ? "RUN " : "STOP", visible_sim ? "SIM " : "ADC ", cfg.rate / 1000000,
         state_name(s));
    text(2, 3, "%s   TRIG #%u   OTR %u   DROP %u   FRAME %u",
         s & 16 ? "AUTO TIMEOUT" : "EDGE TRIGGER", scope_read(R_TRIG), scope_read(R_OTR),
         scope_read(R_DROP), scope_read(R_FRAME));
    text(4, 3, "CH1  12-bit / %s    %s", visible_sim ? "SIM TEST SOURCE" : "AD9226",
         cfg.uv_per_code > 0 ? "VOLTAGE CALIBRATED" : "ADC CODE SCALE / VOLTAGE N/A");
    text(5, 126, "MEASUREMENTS / CH1");
    if (valid_record) {
        text(8, 126, "MIN / MAX  %u / %u", measurement.min, measurement.max);
        text(10, 126, "PkPk       %u code", measurement.max - measurement.min);
        if (cfg.uv_per_code > 0 && !measurement.overrange) {
            text(12, 126, "Vpp        %.4f V",
                 (measurement.max - measurement.min) * cfg.uv_per_code / 1e6);
            double rms = sqrt(fmax(0, measurement.rms * measurement.rms -
                                          2 * cfg.zero * measurement.mean + cfg.zero * cfg.zero)) *
                         cfg.uv_per_code / 1e6;
            text(14, 126, "RMS        %.4f V", rms);
        } else {
            text(12, 126, "Vpp        N/A");
            text(14, 126, "RMS        N/A");
            text(15, 126, measurement.overrange ? "REASON: OVERRANGE" : "REASON: NO CALIBRATION");
        }
        if (measurement.frequency_valid)
            text(17, 126, "FREQ       %.2f Hz", measurement.frequency);
        else {
            text(17, 126, "FREQ       N/A");
            text(18, 126, "NO VALID PERIOD / OTR");
        }
    } else {
        text(8, 126, "WAITING FOR RECORD");
        text(12, 126, "Vpp / RMS / FREQ: N/A");
    }
    text(20, 126, "TRIG %s / %s",
         cfg.trig == 0   ? "AUTO"
         : cfg.trig == 1 ? "NORMAL"
                         : "SINGLE",
         cfg.edge ? "FALL" : "RISE");
    text(21, 126, "LEVEL %u / HYST %u", cfg.level, cfg.hyst);
    if (cfg.mode == EYE) {
        text(23, 126, "2UI / %u bit/s", cfg.bitrate);
        text(24, 126, "REF UNLOCKED / NO CDR");
        text(25, 126, "EYE WIDTH/JITTER: N/A");
    } else if (cfg.mode == FFT) {
        text(23, 126, "FFT %u / %s", cfg.fft_n, cfg.hann ? "HANN" : "RECT");
        text(24, 126, "PEAK %.2f Hz", fft_hz);
        text(25, 126, "LEVEL %.2f dBFS", fft_db);
    } else {
        text(23, 126, "RECORD 16384 samples");
        text(24, 126, "DDR %s", mem_gate ? "MEMTEST PASSED" : "LOCKED / RUN SELFTEST");
        text(25, 126, "MEM %s / SEG %u", mem_valid ? "READY" : "EMPTY", seg_count);
    }
    text(28, 126, "DENSITY HITS %u", hits);
    text(29, 126, "DENSITY DROP %u", drops);
    text(30, 126, "CAP %u / HIST %u", captures_processed, hist_updates);
    text(31, 126, "UI %.1f ms / %.1f Hz", render_ms, frame_hz);
    text(33, 126, "FIFO HWM %u / 4096", scope_read(R_HWM));
    text(34, 126, "DEAD %u samples", scope_read(R_DEAD));
    text(36, 126, "RTL v%08lx", (unsigned long)scope_read(R_VER));
    text(37, 126, "T #%lu:%08lx", (unsigned long)scope_read(R_TIME + 4),
         (unsigned long)scope_read(R_TIME));
    if (err)
        text(38, 3, "FAULT %08lx: %s %s %s", (unsigned long)err, err & 1 ? "FIFO_OVF" : "",
             err & 2 ? "OVERRANGE" : "", err & 4 ? "HIST_DROP" : "");
    text(40, 3, "SPAN %.3f us / %.3f us/div   %s   CAPTURE DEADTIME COUNTED",
         cfg.span * 1e6 / cfg.rate, cfg.span * 1e5 / cfg.rate,
         cfg.uv_per_code > 0 ? "VOLT CAL OK" : "UNCALIBRATED");
    text(42, 3, "Y GAIN x%u / %s / ENCODING %s / HYST %u", 1u << cfg.gain,
         cfg.uv_per_code > 0 ? "VOLT SCALE CONFIGURED" : "V/DIV N/A",
         cfg.encoding ? "TWOS" : "OFFSET", cfg.hyst);

    if (cfg.mode == FFT)
        text(40, 3, "FFT X: 0..%.1f Hz  /  Y: 0..-120 dBFS  /  BIN: %.2f Hz  /  BOXCAR DECIMATION",
             cfg.rate * cfg.fft_n / (2.0 * SCOPE_N), cfg.rate / (double)SCOPE_N);
    if (cfg.mode == EYE)
        text(40, 3,
             "EYE X: 0..2 UI = %.3f us  /  Y: ADC CODE  /  NO REFERENCE LOCK: WIDTH AND JITTER N/A",
             2e6 / cfg.bitrate);
    if (cfg.mode == ROLL)
        text(40, 3, "ROLL: %.3f ms/column / %.3f s total  /  MISSED COLUMNS %u / TIMESTAMP %llu",
             100000.0 * 1000 / cfg.rate, 100000.0 * SCOPE_W / cfg.rate, roll_lost,
             (unsigned long long)roll_time);
    if (cfg.mode == DPX)
        text(39, 3, "DPX 160x90 PL RMW / SATURATING 8-bit / 6x SCALE / DECAY: 1 COUNT PER UPDATE");
    if (cfg.mode == MEM && mem_valid)
        text(40, 3, "MEM 1Mi samples / OFFSET %u / FIRST SAMPLE #%llu / SOURCE %s", cfg.offset,
             (unsigned long long)mem_first_index, mem_source_sim ? "SIM" : "ADC");
    if (cfg.mode == SEG && seg_count)
        text(40, 3, "SEG %u / %u samples / FIRST SAMPLE #%llu / SOURCE %s", cfg.segment,
             segment_len[cfg.segment], (unsigned long long)segment_time[cfg.segment],
             segment_sim[cfg.segment] ? "SIM" : "ADC");
    if (!err && valid_record && measurement.max - measurement.min < 16)
        text(38, 3, "NO_SIGNAL / FLAT INPUT: FREQUENCY N/A");
    text(41, 3, "%s", message);
    text(
        43, 3,
        "K1 short/long: next/prev  K2 short/long: edit/back  BOTH short: menu  BOTH long: RUN/STOP  UART 115200 8N1");
    if (menu) {
        text(5, 5, "MENU / K1 SELECT / K2 CHANGE");
        const char *items[] = {"MODE",
                               "RUN/STOP",
                               "SIM / ADC",
                               "TRIGGER TYPE",
                               "TRIGGER EDGE",
                               "TRIGGER LEVEL",
                               "TIME SPAN",
                               "FFT LENGTH",
                               "FFT WINDOW",
                               "EYE BIT RATE",
                               "VERTICAL GAIN",
                               "ZERO LEVEL",
                               "PLAYBACK OFFSET",
                               "SEGMENT",
                               "MEM CAPTURE",
                               "SINGLE REARM",
                               "ADC RATE",
                               "ENCODING",
                               "SELFTEST / DDR GATE",
                               "CAL uV PER CODE",
                               "TRIGGER HYST"};
        unsigned j;
        for (j = 0; j < 21; j++)
            text(7 + j, 5, "%c %02u %-18s", j == selection ? '>' : ' ', j + 1, items[j]);
    }
}

static uint32_t vertical_scale(uint32_t w) {
    if (cfg.mode == FFT || cfg.mode == EYE || cfg.mode == DPX)
        return w;
    int center = 609 - (int)(cfg.zero * 539 / 4095.0);
    int top = center + (((int)(w & 1023) - center) * (1 << cfg.gain));
    int bottom = center + (((int)(w >> 10) - center) * (1 << cfg.gain));
    if (top < 70)
        top = 70;
    if (top > 609)
        top = 609;
    if (bottom < 70)
        bottom = 70;
    if (bottom > 609)
        bottom = 609;
    return (unsigned)top | ((unsigned)bottom << 10);
}
static void upload(void) {
    unsigned i;
    if (!wait_idle(R_DISPLAY, 1, 60)) {
        set_message("VIDEO COMMIT TIMEOUT");
        reply(0, "code=VIDEO_COMMIT_TIMEOUT frame=%u locks=%08lx", scope_read(R_FRAME),
              (unsigned long)scope_read(R_STATE));
        return;
    }
    uint64_t begin = now();
    draw_ui();
    for (i = 0; i < SCOPE_W; i++)
        scope_write(0x20000 + 4 * i, valid_record ? vertical_scale(wave[i]) : 0);
    if (cfg.mode == DPX || cfg.mode == EYE)
        for (i = 0; i < HIST_W * HIST_H; i++)
            scope_write(0x40000 + 4 * i, hist[i]);
    for (i = 0; i < 7200; i++)
        scope_write(0x80000 + 4 * i, (uint8_t)screen[i]);
    scope_write(R_OWNER, 1 | (menu << 1) | (selection << 2));
    scope_write(R_CRC,
                scope_crc32(screen, sizeof(screen)) ^ scope_crc32(wave, sizeof(wave)) ^
                    ((cfg.mode == DPX || cfg.mode == EYE) ? scope_crc32(hist, sizeof(hist)) : 0));
    scope_write(R_HITS, hits);
    scope_write(R_HDROP, drops);
    scope_write(R_COMMIT, 1);
    render_ms = elapsed_ms(begin);
    refreshes++;
    if (!first_render) {
        first_render = begin;
    }
    double seconds = (begin - first_render) / (double)COUNTS_PER_SECOND;
    if (seconds > 0)
        frame_hz = (refreshes - 1) / seconds;
    dirty = 0;
    last_render = now();
}
static int change_mode(unsigned mode) {
    if (mode > SEG)
        return 0;
    if (mode >= MEM && !mem_gate) {
        set_message("DDR GATE CLOSED: SELFTEST / DMA CRC REQUIRED");
        return 0;
    }
    cfg.run = 0;
    apply();
    if (!wait_idle(R_DISPLAY, 1, 80))
        return 0;
    cfg.mode = mode;
    memset(hist, 0, sizeof(hist));
    if (wait_idle(0xb4, 1, 50))
        scope_write(0xb8, 1);
    cfg.run = 1;
    apply();
    set_message("MODE CHANGED / WAITING FOR FRESH CAPTURE");
    return 1;
}
static void fft_wave(void) {
    unsigned x, j;
    unsigned stride = SCOPE_N / cfg.fft_n;
    scope_fft(record, cfg.fft_n, stride, cfg.hann, cfg.rate, re, im, spectrum, &fft_hz, &fft_db);
    for (x = 0; x < SCOPE_W; x++) {
        unsigned a = (uint64_t)x * (cfg.fft_n / 2) / SCOPE_W,
                 b = (uint64_t)(x + 1) * (cfg.fft_n / 2) / SCOPE_W;
        if (b <= a)
            b = a + 1;
        float peak = -120;
        for (j = a; j < b; j++) {
            if (spectrum[j] > peak)
                peak = spectrum[j];
        }
        if (peak > 0) {
            peak = 0;
        }
        unsigned y = 70 + (unsigned)(-peak * 539 / 120);
        if (y > 609)
            y = 609;
        wave[x] = y | (y << 10);
    }
}

static void pl_hist_point(unsigned x, unsigned y) {
    if (raster_fault)
        return;
    uint64_t start = now();
    while (scope_read(0xd4) & 1) {
        if (elapsed_ms(start) > 10) {
            raster_fault = 1;
            set_message("PL RASTER TIMEOUT");
            reply(0, "code=RASTER_TIMEOUT");
            return;
        }
    }
    scope_write(0xd0, x | (y << 8));
}
static void process_record(void) {
    unsigned t = scope_read(R_TRIG), s = scope_read(R_STATE), i;
    if (!(s & 1) || t == last_record)
        return;
    for (i = 0; i < SCOPE_N; i++)
        record[i] = (uint16_t)scope_read(0x10000 + 4 * i);
    first_index = (((uint64_t)scope_read(R_TIME + 4) << 32) | scope_read(R_TIME)) - 8192;
    last_record = t;
    if (cfg.mode != ROLL)
        valid_record = 1;
    captures_processed++;
    // Release only AFTER copying the frozen ring. All analysis uses this private snapshot.
    scope_write(R_RELEASE, 1);
    scope_measure(record, SCOPE_N, cfg.rate, &measurement);
    if (cfg.mode == FFT)
        fft_wave();
    else if (cfg.mode == DPX || cfg.mode == EYE) {
        if (wait_idle(0xb4, 1, 50)) {
            scope_write(0xb8, 2);
            wait_idle(0xb4, 1, 50);
            raster_fault = 0;
            uint32_t hit_before = scope_read(0xbc);
            scope_set_point_sink(pl_hist_point);
            scope_density(hist, record, SCOPE_N, cfg.rate, cfg.bitrate, cfg.mode == EYE,
                          first_index, 100000, &hits, &drops);
            scope_set_point_sink(0);
            wait_idle(0xd4, 1, 50);
            wait_idle(0xb4, 1, 50);
            for (i = 0; i < HIST_W * HIST_H; i++)
                hist[i] = (uint8_t)scope_read(0xc0000 + 4 * i);
            hits = scope_read(0xbc) - hit_before;
            drops += scope_read(0xc0) + scope_read(0xd8);
            hist_updates++;
        } else
            set_message("HISTOGRAM BUSY TIMEOUT");
    } else if (cfg.mode == SEG && mem_gate) {
        unsigned seg = seg_count % SEGMENTS;
        uint16_t *dst = (uint16_t *)(uintptr_t)(SEG_BUFFER + seg * SCOPE_N * 2);
        memcpy(dst, record, sizeof(record));
        Xil_DCacheFlushRange((UINTPTR)dst, sizeof(record));
        segment_time[seg] = first_index;
        segment_sim[seg] = cfg.sim;
        segment_len[seg] = SCOPE_N;
        seg_count++;
        scope_envelope(record, SCOPE_N, (SCOPE_N - cfg.span) / 2, cfg.span, wave);
    } else if (cfg.mode != MEM && cfg.mode != ROLL)
        scope_envelope(record, SCOPE_N, (SCOPE_N - cfg.span) / 2, cfg.span, wave);
    dirty = 1;
}
static int memory_test(void) {
    uint32_t *p = (uint32_t *)DMA_BUFFER;
    unsigned i, n = DMA_BUFFER_BYTES / 4;
    uint64_t begin = now();
    if (dma_read(0x34) & 0x1) { /* Halted is expected before transfer. */
    }
    for (i = 0; i < n; i++)
        p[i] = 0x92267010u ^ (i * 2654435761u);
    Xil_DCacheFlushRange(DMA_BUFFER, DMA_BUFFER_BYTES);
    Xil_DCacheInvalidateRange(DMA_BUFFER, DMA_BUFFER_BYTES);
    for (i = 0; i < n; i++)
        if (p[i] != (0x92267010u ^ (i * 2654435761u))) {
            reply(0, "code=DDR_COMPARE index=%u", i);
            return 0;
        }
    reply(1, "memory=PASS region=0x10000000..0x101FFFFF bytes=%u time_ms=%.2f", DMA_BUFFER_BYTES,
          elapsed_ms(begin));
    return 1;
}
static int memory_capture(int verify_sim) {
    unsigned old_sim = cfg.sim, old_run = cfg.run;
    uint32_t drop_before = scope_read(R_DROP);
    dma_irq = 0;
    dma_errors = 0;
    if (verify_sim) {
        cfg.sim = 1;
        cfg.run = 1;
        apply();
        usleep(1000);
    }
    dma_write(0x30, 4);
    uint64_t begin = now();
    while (dma_read(0x30) & 4)
        if (elapsed_ms(begin) > 100) {
            reply(0, "code=DMA_RESET_TIMEOUT");
            goto fail;
        }
    Xil_DCacheFlushRange(DMA_BUFFER, DMA_BUFFER_BYTES);
    Xil_DCacheInvalidateRange(DMA_BUFFER, DMA_BUFFER_BYTES);
    dma_write(0x34, 0x7000);
    dma_irq = 0;
    dma_errors = 0;
    dma_write(0x30, 0x5001);
    dma_write(0x48, DMA_BUFFER);
    dma_write(0x58, DMA_BUFFER_BYTES);
    scope_write(R_DMA_START, 2);
    usleep(2000);
    scope_write(R_DMA_LEN, DMA_BUFFER_BYTES / 2);
    scope_write(R_DMA_START, 1);
    begin = now();
    while (!dma_irq && !(dma_read(0x34) & 0x1000)) {
        if ((dma_read(0x34) & 0x770) || dma_errors || elapsed_ms(begin) > 2000) {
            reply(0, "code=DMA_TRANSFER status=%08lx", (unsigned long)dma_read(0x34));
            mem_gate = 0;
            goto fail;
        }
    }
    if (dma_errors || (dma_read(0x34) & 0x770)) {
        reply(0, "code=DMA_IRQ_ERROR");
        goto fail;
    }
    double ms = elapsed_ms(begin);
    Xil_DCacheInvalidateRange(DMA_BUFFER, DMA_BUFFER_BYTES);
    if (scope_read(R_DROP) != drop_before) {
        reply(0, "code=FIFO_DROP");
        goto fail;
    }
    const uint16_t *p = (uint16_t *)DMA_BUFFER;

    if (verify_sim) {
        uint32_t phase;
        unsigned bad_index;
        if (!scope_validate_dds(p, DMA_BUFFER_BYTES / 2, 16777, &phase, &bad_index)) {
            reply(0, "code=DMA_SIM_COMPARE index=%u", bad_index);
            goto fail;
        }
    }
    uint32_t crc = scope_crc32(p, DMA_BUFFER_BYTES);
    mem_valid = 1;
    mem_source_sim = cfg.sim;
    mem_first_index = ((uint64_t)scope_read(0xe4) << 32) | scope_read(0xe0);
    reply(1, "dma=PASS bytes=%u time_ms=%.3f payload_MBps=%.3f crc32=%08lx sim=%u",
          DMA_BUFFER_BYTES, ms, DMA_BUFFER_BYTES / (ms * 1000), (unsigned long)crc, verify_sim);
    if (verify_sim) {
        cfg.sim = old_sim;
        cfg.run = old_run;
        apply();
    }
    return 1;
fail:
    dma_write(0x30, 4);
    scope_write(R_DMA_START, 2);
    mem_gate = 0;
    mem_valid = 0;
    if (verify_sim) {
        cfg.sim = old_sim;
        cfg.run = old_run;
        apply();
    }
    return 0;
}
static void selftest(void) {
    if (scope_read(R_ID) != 0x53434f50) {
        reply(0, "code=PL_ID");
        return;
    }
    uint32_t f = scope_read(R_FRAME);
    usleep(40000);
    if (scope_read(R_FRAME) == f) {
        reply(0, "code=VIDEO_FRAME_STUCK");
        return;
    }
    if (!memory_test() || !memory_capture(1)) {
        mem_gate = 0;
        set_message("SELFTEST FAILED / MEM & SEG DISABLED");
        return;
    }
    mem_gate = 1;
    set_message("SELFTEST PASSED AT CURRENT RATE / HIGH-RATE DDR UNQUALIFIED");
    reply(1, "selftest=PASS rate=%u higher_rates=UNQUALIFIED", cfg.rate);
}
static void status(void) {
    reply(
        1,
        "mode=%s run=%u source=%s rate=%u state=%s frame=%u samples=%lu:%08lx otr=%u drop=%u errors=%08lx dead=%u mem_gate=%u irq_lost=%u",
        modes[cfg.mode], cfg.run, cfg.sim ? "SIM" : "ADC", cfg.rate,
        state_name(scope_read(R_STATE)), scope_read(R_FRAME),
        (unsigned long)scope_read(R_SAMPLES + 4), (unsigned long)scope_read(R_SAMPLES),
        scope_read(R_OTR), scope_read(R_DROP), (unsigned long)scope_read(R_ERRORS),
        scope_read(R_DEAD), mem_gate, key_lost);
}
static void edit(int direction) {
    unsigned next;
    switch (selection) {
    case 0:
        next = (cfg.mode + 7 + direction) % 7;
        for (unsigned i = 0; i < 7; i++) {
            if (next < MEM || mem_gate)
                break;
            next = (next + 7 + direction) % 7;
        }
        change_mode(next);
        break;
    case 1:
        cfg.run ^= 1;
        apply();
        break;
    case 2:
        cfg.sim ^= 1;
        apply();
        break;
    case 3:
        cfg.trig = (cfg.trig + 3 + direction) % 3;
        apply();
        break;
    case 4:
        cfg.edge ^= 1;
        apply();
        break;
    case 5:
        cfg.level = (cfg.level + 4096 + direction * 128) % 4096;
        apply();
        break;
    case 6:
        if (direction > 0)
            cfg.span = cfg.span < 16384 ? cfg.span * 2 : 1024;
        else
            cfg.span = cfg.span > 1024 ? cfg.span / 2 : 16384;
        break;
    case 7:
        if (direction > 0)
            cfg.fft_n = cfg.fft_n < 4096 ? cfg.fft_n * 2 : 1024;
        else
            cfg.fft_n = cfg.fft_n > 1024 ? cfg.fft_n / 2 : 4096;
        break;
    case 8:
        cfg.hann ^= 1;
        break;
    case 9:
        cfg.bitrate = (cfg.bitrate / 1000000 + 5 + direction - 1) % 5 * 1000000 + 1000000;
        memset(hist, 0, sizeof(hist));
        break;
    case 19:
        cfg.uv_per_code = cfg.uv_per_code > 0 ? cfg.uv_per_code * (direction > 0 ? 1.1 : 0.9) : 100;
        set_message("MANUAL CALIBRATION SCALE / VERIFY WITH KNOWN INPUT");
        break;
    case 10:
        cfg.gain = (cfg.gain + 4 + direction) % 4;
        break;
    case 11:
        cfg.zero = fmax(0, fmin(4095, cfg.zero + direction * 16));
        break;
    case 12:
        cfg.offset = (cfg.offset + 1048576 + direction * 16384) % 1048576;
        break;
    case 13:
        cfg.segment = (cfg.segment + 8 + direction) % 8;
        break;
    case 14:
        if (mem_gate)
            memory_capture(0);
        else
            set_message("RUN UART selftest FIRST");
        break;
    case 15:
        apply();
        break;
    case 16:
        set_message("ADC RATE: 10MHz UNTIL G2 TIMING/HIL QUALIFIED");
        break;
    case 17:
        cfg.encoding ^= 1;
        apply();
        break;
    case 18:
        selftest();
        break;
    case 20:
        cfg.hyst = (cfg.hyst + 256 + direction * 4) % 256;
        apply();
        break;
    }
    dirty = 1;
}
static void handle_keys(void) {
    while (key_tail != key_head) {
        uint32_t e = key_queue[key_tail];
        key_tail = (key_tail + 1) & 15;
        unsigned keys = e & 3, longpress = (e >> 2) & 1;
        if (keys == 3) {
            if (longpress) {
                cfg.run ^= 1;
                apply();
            } else
                menu ^= 1;
        } else if (keys == 1)
            selection = (selection + 21 + (longpress ? -1 : 1)) % 21;
        else if (keys == 2) {
            if (longpress && menu)
                menu = 0;
            else
                edit(longpress ? -1 : 1);
        }
        dirty = 1;
    }
}
static void dispatch(char *line) {
    char *a[8], *p = strtok(line, " ");
    unsigned n = 0;
    while (p && n < 8) {
        a[n++] = p;
        p = strtok(0, " ");
    }
    if (!n)
        return;
    if (!strcmp(a[0], "help")) {
        reply(
            1,
            "help ver selftest status clocks capture trigger dma dpx errors mode run menu trig adc fft eye cal memory config");
        return;
    }
    if (!strcmp(a[0], "ver")) {
        reply(
            1,
            "product=Z7_SCOPE fw=3.0 rtl=%08lx source_sha=%08lx id=%08lx SDK=2018.3 qualification=BENCH_PENDING",
            (unsigned long)scope_read(R_VER), (unsigned long)scope_read(0xf4),
            (unsigned long)scope_read(R_ID));
        return;
    }
    if (n == 2 && !strcmp(a[0], "errors") && !strcmp(a[1], "clear")) {
        scope_write(R_ERRORS, 0xffffffff);
        reply(1, "errors_cleared");
        return;
    }
    if (!strcmp(a[0], "status") || !strcmp(a[0], "capture") || !strcmp(a[0], "trigger") ||
        !strcmp(a[0], "errors")) {
        status();
        return;
    }
    if (!strcmp(a[0], "clocks")) {
        reply(
            1,
            "adc=%u sys=100000000 video_profile=%u pixel=%u tmds=%u lock=%03lx qualification_mask=%x",
            scope_read(R_RATE), scope_read(0xf0), scope_read(0xf0) ? 25200000 : 74250000,
            scope_read(0xf0) ? 126000000 : 371250000, (unsigned long)scope_read(R_STATE),
            qualified_rate_mask);
        return;
    }
    if (!strcmp(a[0], "dma")) {
        reply(1, "s2mm=%08lx bytes=%u accepted=%u drop=%u hwm=%u", (unsigned long)dma_read(0x34),
              scope_read(R_DMA_BYTES), scope_read(R_DMA_ACCEPT), scope_read(R_DROP),
              scope_read(R_HWM));
        return;
    }
    if (!strcmp(a[0], "dpx")) {
        reply(1, "size=%ux%u hits=%u explicit_drop=%u updates=%u captures=%u", HIST_W, HIST_H, hits,
              drops, hist_updates, captures_processed);
        return;
    }
    if (!strcmp(a[0], "selftest")) {
        selftest();
        return;
    }
    if (n >= 2 && !strcmp(a[0], "mode")) {
        unsigned i;
        for (i = 0; i < 7; i++) {
            char lower[8];
            unsigned j;
            for (j = 0; modes[i][j]; j++)
                lower[j] = modes[i][j] + 32;
            lower[j] = 0;
            if (!strcmp(a[1], lower)) {
                reply(change_mode(i), "mode=%s gate=%u", modes[i], mem_gate);
                return;
            }
        }
    }
    if (n == 2 && !strcmp(a[0], "run")) {
        if (strcmp(a[1], "0") && strcmp(a[1], "1"))
            goto bad;
        cfg.run = atoi(a[1]);
        reply(apply(), "run=%u", cfg.run);
        return;
    }
    if (n >= 2 && !strcmp(a[0], "menu")) {
        if (!strcmp(a[1], "toggle"))
            menu ^= 1;
        else if (!strcmp(a[1], "next"))
            selection = (selection + 1) % 21;
        else if (!strcmp(a[1], "prev"))
            selection = (selection + 20) % 21;
        else if (!strcmp(a[1], "back"))
            menu = 0;
        else if (!strcmp(a[1], "edit"))
            edit(1);
        else
            goto bad;
        dirty = 1;
        reply(1, "menu=%u item=%u", menu, selection);
        return;
    }
    if (n == 3 && !strcmp(a[0], "trig")) {
        if (!strcmp(a[1], "level")) {
            long v = strtol(a[2], 0, 0);
            if (v < 0 || v > 4095)
                goto bad;
            cfg.level = v;
        } else if (!strcmp(a[1], "edge")) {
            if (strcmp(a[2], "rise") && strcmp(a[2], "fall"))
                goto bad;
            cfg.edge = !strcmp(a[2], "fall");
        } else if (!strcmp(a[1], "type")) {
            if (!strcmp(a[2], "auto"))
                cfg.trig = 0;
            else if (!strcmp(a[2], "normal"))
                cfg.trig = 1;
            else if (!strcmp(a[2], "single"))
                cfg.trig = 2;
            else
                goto bad;
        } else
            goto bad;
        reply(apply(), "trigger_updated");
        return;
    }
    if (n == 3 && !strcmp(a[0], "adc")) {
        if (!strcmp(a[1], "source")) {
            if (strcmp(a[2], "sim") && strcmp(a[2], "real"))
                goto bad;
            cfg.sim = !strcmp(a[2], "sim");
            reply(apply(), "source=%s", cfg.sim ? "SIM" : "ADC");
            return;
        }
        if (!strcmp(a[1], "rate")) {
            unsigned rate = atoi(a[2]), index = rate == 10   ? 0
                                                : rate == 25 ? 1
                                                : rate == 50 ? 2
                                                : rate == 65 ? 3
                                                             : 99;
            if (index == 99)
                goto bad;
            if (!(qualified_rate_mask & (1u << index))) {
                reply(0, "code=RATE_UNQUALIFIED requested=%uM G2_HIL_REQUIRED", rate);
                return;
            }
            cfg.run = 0;
            apply();
            usleep(1000);
            scope_write(R_RATE, index);
            usleep(1000);
            cfg.rate = rate * 1000000;
            cfg.run = 1;
            reply(apply(), "rate=%u", cfg.rate);
            return;
        }
        if (!strcmp(a[1], "encoding")) {
            if (strcmp(a[2], "twos") && strcmp(a[2], "offset"))
                goto bad;
            cfg.encoding = !strcmp(a[2], "twos");
            apply();
            reply(1, "encoding=%s", a[2]);
            return;
        }
    }
    if (n == 3 && !strcmp(a[0], "fft")) {
        if (!strcmp(a[1], "n")) {
            unsigned z = atoi(a[2]);
            if (z != 1024 && z != 2048 && z != 4096)
                goto bad;
            cfg.fft_n = z;
        } else if (!strcmp(a[1], "window")) {
            if (strcmp(a[2], "hann") && strcmp(a[2], "rect"))
                goto bad;
            cfg.hann = !strcmp(a[2], "hann");
        } else
            goto bad;
        dirty = 1;
        reply(1, "fft_n=%u hann=%u", cfg.fft_n, cfg.hann);
        return;
    }
    if (n == 3 && !strcmp(a[0], "eye") && !strcmp(a[1], "rate")) {
        unsigned z = atoi(a[2]);
        if (z < 1000000 || z > 5000000)
            goto bad;
        cfg.bitrate = z;
        memset(hist, 0, sizeof(hist));
        dirty = 1;
        reply(1, "bitrate=%u lock=UNLOCKED eye_width=N/A jitter=N/A", z);
        return;
    }
    if (n == 3 && !strcmp(a[0], "cal")) {
        double scale = strtod(a[1], 0), zero = strtod(a[2], 0);
        if (!isfinite(scale) || !isfinite(zero) || scale <= 0 || scale > 100000 || zero < 0 ||
            zero > 4095)
            goto bad;
        cfg.uv_per_code = scale;
        cfg.zero = zero;
        dirty = 1;
        reply(1, "cal_uv_per_code=%.6f zero=%.3f", scale, zero);
        return;
    }
    if (n >= 2 && !strcmp(a[0], "memory")) {
        if (!strcmp(a[1], "test")) {
            memory_test();
            return;
        }
        if (!strcmp(a[1], "capture")) {
            if (!mem_gate) {
                reply(0, "code=DDR_GATE_CLOSED");
                return;
            }
            memory_capture(0);
            return;
        }
    }
    if (n == 2 && !strcmp(a[0], "config")) {
        if (!strcmp(a[1], "save"))
            saved = cfg;
        else if (!strcmp(a[1], "load")) {
            if (!saved.rate) {
                reply(0, "code=NO_SAVED_CONFIG");
                return;
            }
            if (saved.mode >= MEM && !mem_gate) {
                reply(0, "code=DDR_GATE_CLOSED");
                return;
            }
            cfg = saved;
            apply();
        } else
            goto bad;
        reply(1, "config=%s storage=VOLATILE_RAM", a[1]);
        return;
    }
bad:
    reply(0, "code=INVALID_COMMAND_OR_ARGUMENT use=help");
}

static void process_roll(void) {
    if (cfg.mode != ROLL || !cfg.run)
        return;
    unsigned seq = scope_read(0x94);
    if (seq == roll_sequence)
        return;
    unsigned advance = roll_sequence ? seq - roll_sequence : 1;
    if (advance > SCOPE_W)
        advance = SCOPE_W;
    if (roll_sequence && seq - roll_sequence > 1)
        roll_lost += seq - roll_sequence - 1;
    roll_sequence = seq;
    unsigned v = scope_read(0x90), lo = v & 4095, hi = (v >> 12) & 4095;
    roll_time = ((uint64_t)scope_read(0x9c) << 32) | scope_read(0x98);
    memmove(wave, wave + advance, (SCOPE_W - advance) * sizeof(*wave));
    for (unsigned i = SCOPE_W - advance; i < SCOPE_W - 1; i++)
        wave[i] = 0;
    unsigned top = 609 - hi * 539 / 4095, bottom = 609 - lo * 539 / 4095;
    wave[SCOPE_W - 1] = top | (bottom << 10);
    if (roll_columns < SCOPE_W)
        roll_columns++;
    valid_record = 1;
    dirty = 1;
}
static void poll_uart(void) {
    while (XUartPs_IsReceiveData(XPAR_XUARTPS_0_BASEADDR)) {
        unsigned ch = XUartPs_ReadReg(XPAR_XUARTPS_0_BASEADDR, XUARTPS_FIFO_OFFSET);
        if (ch == '\r' || ch == '\n') {
            if (command_len) {
                command[command_len] = 0;
                dispatch(command);
                command_len = 0;
            }
        } else if (ch == 8 || ch == 127) {
            if (command_len)
                command_len--;
        } else if (ch >= 32 && ch < 127) {
            if (command_len < sizeof(command) - 1)
                command[command_len++] = ch;
            else {
                command_len = 0;
                reply(0, "code=COMMAND_TOO_LONG");
            }
        }
    }
}
int main(void) {
    Xil_ICacheEnable();
    Xil_DCacheEnable();
    printf("\r\nZ7_SCOPE BOOT fw=3.0 SDK=2018.3 DDR DMA reserved 0x10000000..0x105FFFFF\r\n");
    if (scope_read(R_ID) != 0x53434f50) {
        printf("ERR code=PL_ID_MISMATCH\r\n");
        return 1;
    }
    if (!interrupts_init())
        printf("ERR code=GIC_INIT\r\n");
    while (scope_read(0x80) != 0) {
    }
    scope_write(R_OWNER, 1);
    apply();
    last_render = now();
    for (;;) {
        poll_uart();
        handle_keys();
        process_roll();
        process_record();
        if (cfg.mode == MEM && mem_valid) {
            uint16_t *p = (uint16_t *)DMA_BUFFER;
            unsigned start = cfg.offset;
            if (start + cfg.span > 1048576)
                start = 1048576 - cfg.span;
            scope_envelope(p, 1048576, start, cfg.span, wave);
            scope_measure(p + start, cfg.span, cfg.rate, &measurement);
            valid_record = 1;
        }
        if (cfg.mode == SEG && seg_count) {
            unsigned s = cfg.segment % SEGMENTS;
            if (segment_len[s]) {
                uint16_t *p = (uint16_t *)(uintptr_t)(SEG_BUFFER + s * SCOPE_N * 2);
                scope_envelope(p, SCOPE_N, (SCOPE_N - cfg.span) / 2, cfg.span, wave);
                scope_measure(p + (SCOPE_N - cfg.span) / 2, cfg.span, cfg.rate, &measurement);
                valid_record = 1;
            } else
                valid_record = 0;
        }
        if ((dirty || elapsed_ms(last_render) > 1000) && elapsed_ms(last_render) > 100)
            upload();
    }
}
