/* Z7-Lite scope firmware, SDK 2018.3 standalone. No flash writes. */
#include "xparameters.h"
#include "xil_cache.h"
#include "xil_exception.h"
#include "xscugic.h"
#include "xuartps_hw.h"
#include "xuartps.h"
#include "xtime_l.h"
#include "sleep.h"
#include "scope_analysis.h"
#include "scope_hw.h"
#include "scope_debug.h"
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#ifndef SCOPE_FW_SHA
#define SCOPE_FW_SHA 0
#endif

enum { DSO, DPX, EYE, FFT, ROLL, MEM, SEG };
static const char *modes[] = {"DSO", "DPX", "EYE", "FFT", "ROLL", "MEM", "SEG"};
typedef struct {
    unsigned mode, run, sim, level, hyst, edge, trig, rate, fft_n, hann, bitrate, span, segment,
        offset, encoding, gain;
    double uv_per_code, zero, cal_zero;
} settings;
static settings cfg = {DSO,
                       1,
                       0,
                       2048,
                       8,
                       0,
                       0,
                       10000000,
                       4096,
                       1,
                       1000000,
                       4096,
                       0,
                       0,
                       0,
                       0,
                       10000000.0 / 4095.0,
                       2047.5,
                       2047.5},
                saved;
static uint16_t record[SCOPE_N] __attribute__((aligned(64)));
static uint32_t wave[SCOPE_W];
static uint8_t hist[HIST_W * HIST_H];
static float re[4096], im[4096], spectrum[2048];
static uint16_t screen[2400];
static char command[160];
static unsigned adc_calibrated, auto_scale, saved_calibrated, saved_auto_scale;
static unsigned command_len, sequence, menu, selection;
static unsigned mem_gate, mem_valid, seg_count, last_record, valid_record, refreshes,
    captures_processed, hist_updates, key_lost, dirty = 1;
static uint32_t hits, drops;
static unsigned roll_sequence, roll_columns, roll_lost;
static uint64_t roll_time;
static unsigned mem_source_sim, segment_sim[SEGMENTS], raster_fault, record_source_sim;
static uint64_t mem_first_index;
static uint64_t segment_time[SEGMENTS], first_index;
static unsigned segment_len[SEGMENTS];
static uint32_t segment_crc[SEGMENTS];
static unsigned last_key_sequence;
static volatile unsigned key_head, key_tail;
static volatile uint32_t key_queue[16];
static volatile unsigned dma_irq, dma_errors;
static XScuGic gic;
static scope_measurements measurement;
static double fft_hz, fft_db, render_ms, frame_hz;
static uint64_t last_render, first_render;
static char message[90] = "REAL ADC / UNCALIBRATED / MEM & SEG REQUIRE SELFTEST";
static unsigned qualified_rate_mask = 15; /* Four clock modes must pass release STA and digital HIL.
                                             Analog calibration remains separate. */
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
static unsigned debug_reply_active;
static uint32_t rpc_id;
static volatile unsigned uart_head, uart_tail, uart_lost;
static volatile unsigned char uart_rx[1024];
static void reply(int ok, const char *fmt, ...) {
    char payload[512], line[560];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(payload, sizeof(payload), fmt, ap);
    va_end(ap);
    snprintf(line, sizeof(line), "%s seq=%u rid=%08lx %s\r\n", ok ? "OK" : "ERR", ++sequence,
             (unsigned long)rpc_id, payload);
    printf("%s", line);
    if (debug_reply_active) {
        volatile scope_debug_mailbox *m = DEBUG_MAILBOX;
        unsigned n = m->length;
        for (unsigned i = 0; line[i] && n + 1 < sizeof(m->response); i++)
            m->response[n++] = line[i];
        m->response[n] = 0;
        m->length = n;
        if (!ok)
            m->flags |= 1;
    }
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
    unsigned old_ctrl = scope_read(R_CTRL);
    if (((old_ctrl >> 1) & 1) != cfg.sim || ((old_ctrl >> 6) & 1) != cfg.encoding) {
        valid_record = 0;
        memset(&measurement, 0, sizeof(measurement));
        record_source_sim = cfg.sim;
        fft_hz = 0;
        fft_db = -160;
        memset(hist, 0, sizeof(hist));
        memset(wave, 0, sizeof(wave));
        roll_sequence = 0;
        roll_columns = 0;
        if (wait_idle(0xb4, 1, 50))
            scope_write(0xb8, 1);
    }
    scope_write(R_CTRL, (cfg.run ? 1 : 0) | (cfg.sim ? 2 : 0) | (cfg.edge ? 4 : 0) |
                            (cfg.trig << 3) | (cfg.encoding << 6) | (cfg.level << 8) |
                            (cfg.hyst << 20));
    scope_write(R_MODE, cfg.mode);
    if (!wait_idle(R_STATE, 1u << 9, 50)) {
        set_message("ADC CONFIG ACK TIMEOUT");
        return 0;
    }
    /* Two complete status scans plus handshake margin drain any pre-configuration ready message. */
    usleep(2 * 256 * 1000000 / cfg.rate + 10);
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
static void uart_isr(void *unused) {
    (void)unused;
    while (XUartPs_IsReceiveData(XPAR_XUARTPS_0_BASEADDR)) {
        unsigned ch = XUartPs_ReadReg(XPAR_XUARTPS_0_BASEADDR, XUARTPS_FIFO_OFFSET);
        unsigned next = (uart_head + 1) & 1023;
        if (next == uart_tail)
            uart_lost++;
        else {
            uart_rx[uart_head] = (unsigned char)ch;
            uart_head = next;
        }
    }
    XUartPs_WriteReg(XPAR_XUARTPS_0_BASEADDR, XUARTPS_ISR_OFFSET, 0xffffffff);
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
    XScuGic_SetPriorityTriggerType(&gic, 59, 0x90, 1);
    XScuGic_Connect(&gic, 59, uart_isr, 0);
    XScuGic_Enable(&gic, 59);
    XUartPs_WriteReg(XPAR_XUARTPS_0_BASEADDR, XUARTPS_RXWM_OFFSET, 16);
    XUartPs_WriteReg(XPAR_XUARTPS_0_BASEADDR, XUARTPS_RXTOUT_OFFSET, 8);
    XUartPs_WriteReg(XPAR_XUARTPS_0_BASEADDR, XUARTPS_ISR_OFFSET, 0xffffffff);
    XUartPs_WriteReg(XPAR_XUARTPS_0_BASEADDR, XUARTPS_IER_OFFSET,
                     XUARTPS_IXR_RXOVR | XUARTPS_IXR_TOUT);
    Xil_ExceptionEnable();
    return 1;
}
#include "scope_dac_control.h"
#include "scope_ui_font.h"

static void text(unsigned row, unsigned col, const char *fmt, ...) {
    char str[320];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(str, sizeof(str), fmt, ap);
    va_end(ap);
    const unsigned char *p = (const unsigned char *)str;
    while (*p && row < 30 && col < 80) {
        unsigned ch = *p++;
        if (ch >= 0xe0 && ch < 0xf0 && p[0] && p[1]) {
            ch = ((ch & 15) << 12) | ((p[0] & 63) << 6) | (p[1] & 63);
            p += 2;
        } else if (ch >= 0xc0 && ch < 0xe0 && p[0]) {
            ch = ((ch & 31) << 6) | (p[0] & 63);
            p++;
        }
        screen[row * 80 + col++] = ui_glyph(ch);
    }
}
static const char *state_name(unsigned s) {
    static const char *names[] = {"空闲", "预采集", "等待触发", "后采集",
                                  "保持", "错误",   "错误",     "错误"};
    return names[(s >> 1) & 7];
}
static unsigned displayed_source_sim(void) {
    if (cfg.mode == MEM && mem_valid)
        return mem_source_sim;
    if (cfg.mode == SEG && segment_len[cfg.segment])
        return segment_sim[cfg.segment];
    return valid_record ? record_source_sim : cfg.sim;
}
static unsigned dac_plot_lo, dac_plot_hi = 16383;
static uint32_t dac_preview(unsigned x) {
    unsigned index = (x * 2u * DAC_N / SCOPE_W) % DAC_N;
    unsigned value = dac_table[index];
    unsigned y = 609 - (value - dac_plot_lo) * 539u / (dac_plot_hi - dac_plot_lo);
    unsigned prev = x ? (x - 1) * 2u * DAC_N / SCOPE_W % DAC_N : index;
    unsigned y0 = 609 - (dac_table[prev] - dac_plot_lo) * 539u / (dac_plot_hi - dac_plot_lo);
    return (y < y0 ? y : y0) | ((y > y0 ? y : y0) << 10);
}
static void unit_text(char *out, unsigned size, double value, const char *unit) {
    double a = fabs(value);
    if (a >= 1e6)
        snprintf(out, size, "%.2f M%s", value / 1e6, unit);
    else if (a >= 1e3)
        snprintf(out, size, "%.2f k%s", value / 1e3, unit);
    else if (a > 0 && a < 1e-3)
        snprintf(out, size, "%.1f us", value * 1e6);
    else if (a > 0 && a < 1)
        snprintf(out, size, "%.2f ms", value * 1e3);
    else
        snprintf(out, size, "%.2f %s", value, unit);
}
static void axes(void) {
    // Grid x=80..1040 with ten divisions; y=70..609. Each label is
    // derived from exactly the same transfer used for the plotted samples.
    unsigned fft = (!page_dac && cfg.mode == FFT), eye = (!page_dac && cfg.mode == EYE);
    for (unsigned j = 0; j <= 10; j += 2) {
        double value;
        if (page_dac)
            value = (2.0 * j / 10) / dac_frequency;
        else if (fft)
            value = (double)cfg.rate * cfg.fft_n / (2 * SCOPE_N) * j / 10;
        else if (eye)
            value = 2.0 * j / 10;
        else if (cfg.mode == ROLL)
            value = -(10 - j) * 100000.0 * SCOPE_W / (10 * cfg.rate);
        else if (cfg.mode == DPX)
            value = (j - 5.0) * SCOPE_N / (10 * cfg.rate);
        else if (cfg.mode == MEM)
            value = (fmin(cfg.offset, 1048576 - cfg.span) + j * cfg.span / 10.0) / (double)cfg.rate;
        else
            value = (j - 5.0) * cfg.span / (10 * cfg.rate);
        char label[32];
        if (eye)
            snprintf(label, sizeof(label), "%.1f UI", value);
        else
            unit_text(label, sizeof(label), value, fft ? "Hz" : "s");
        int centered = (80 + 96 * (int)j) / 16 - (int)strlen(label) / 2;
        unsigned col = centered < 0 ? 0 : (unsigned)centered;
        if (col + strlen(label) > 80)
            col = 80 - strlen(label);
        text(26, col, "%s", label);
    }
    for (unsigned j = 0; j <= 10; j += 2) {
        double code = 4095 * (1 - j / 10.0);
        unsigned row = (70 + j * 54) / 24;
        if (row >= 26)
            row = 25;
        if (page_dac)
            text(row, 0, "%4.1f",
                 100 * (dac_plot_hi - (dac_plot_hi - dac_plot_lo) * j / 10.0) / 16383.0);
        else if (fft)
            text(row, 0, "%4d", -(int)j * 12);
        else {
            if (cfg.mode != EYE && cfg.mode != DPX)
                code = cfg.zero + (code - 2047.5) / (1u << cfg.gain);
            if (cfg.uv_per_code > 0)
                text(row, 0, "%4.2f", (code - cfg.cal_zero) * cfg.uv_per_code / 1e6);
            else
                text(row, 0, "%4.0f", code);
        }
    }
    text(2, 5, "%s", page_dac ? "%FS" : fft ? "dBFS" : cfg.uv_per_code > 0 ? "V" : "码值");
    if (!page_dac && (cfg.mode == DPX || cfg.mode == EYE))
        text(24, 8, "颜色强度:命中计数 1..255 / 衰减累积");
}
static void draw_ui(void) {
    for (unsigned i = 0; i < 2400; i++)
        screen[i] = ' ';
    unsigned state = scope_read(R_STATE), sim = displayed_source_sim();
    uint32_t err = scope_read(R_ERRORS);
    const char *names[] = {"示波器", "DPX", "EYE", "FFT", "滚动", "长存储", "分段"};
    text(0, 1, "Z7 LAB");
    text(0, 12, "%s / %s", page_dac ? "DAC 信号发生器" : "ADC 数字示波器",
         page_dac ? "独立输出" : names[cfg.mode]);
    text(0, 67, "%s", page_dac ? (dac_on ? "输出开启" : "保持中点") : (cfg.run ? "RUN" : "STOP"));
    text(1, 1, "%s", page_dac ? "DAC904  14 bit  50 MSa/s" : "AD9226  12 bit");
    if (page_dac)
        text(1, 34, "配置预览 / 非输出实测");
    else
        text(1, 24, "%u MSa/s  %s  %s", cfg.rate / 1000000, sim ? "SIM 测试源" : "ADC 实际输入",
             state_name(state));
    if (page_dac) {
        unsigned lo = 16383, hi = 0;
        for (unsigned i = 0; i < DAC_N; i++) {
            if (dac_table[i] < lo)
                lo = dac_table[i];
            if (dac_table[i] > hi)
                hi = dac_table[i];
        }
        unsigned margin = (hi - lo) / 8;
        if (margin < 80)
            margin = 80;
        dac_plot_lo = lo > margin ? lo - margin : 0;
        dac_plot_hi = hi + margin < 16383 ? hi + margin : 16383;
    }
    axes();
    if (page_dac) {
        const char *shapes[] = {"正弦波", "方波", "三角波", "锯齿波", "直流", "自定义"};
        text(3, 67, "波形类型");
        text(4, 67, "%s", shapes[dac_shape]);
        text(6, 67, "实际设定频率");
        text(7, 67, "%.2f Hz", dac_frequency);
        text(9, 67, "峰峰值 / FS");
        text(10, 67, "%.2f %%", dac_amplitude * 100);
        text(12, 67, "偏置 / FS");
        text(13, 67, "%.2f %%", dac_offset * 100);
        text(15, 67, "占空比");
        text(16, 67, "%.2f %%", dac_duty * 100);
        text(18, 67, "波形校验 CRC");
        text(19, 67, "%08lx", (unsigned long)dac_crc);
        text(21, 67, "ADC 独立运行");
        text(22, 67, "%s %uM", modes[cfg.mode], cfg.rate / 1000000);
        text(24, 67, "电压未校准");
        text(27, 1, "DAC 配置预览:横轴时间 / 纵轴满量程百分比 / 双周期");
        text(28, 1, "DAC 标称 5Vpp / 默认关闭 / ADC 模块标称量程 ±5V @50Ω");
        text(29, 1, "上位机:独立 DAC 控制 / 数学表达式 / CSV / 波形上传与校验");
        return;
    }
    text(3, 67, "频率");
    if (valid_record && measurement.frequency_valid)
        text(4, 67, "%.2f Hz", measurement.frequency);
    else
        text(4, 67, "N/A");
    text(6, 67, "峰峰值");
    if (valid_record && cfg.uv_per_code > 0)
        text(7, 67, "%.4f V", (measurement.max - measurement.min) * cfg.uv_per_code / 1e6);
    else if (valid_record)
        text(7, 67, "%u 码值", measurement.max - measurement.min);
    else
        text(7, 67, "等待采样");
    text(9, 67, "RMS / %s", adc_calibrated ? "已校准" : "标称值");
    double rms_v =
        sqrt(fmax(0, measurement.rms * measurement.rms - 2 * cfg.cal_zero * measurement.mean +
                         cfg.cal_zero * cfg.cal_zero)) *
        cfg.uv_per_code / 1e6;
    text(10, 67, "%.4f V", rms_v);
    text(11, 67, "均值 %.3f V", (measurement.mean - cfg.cal_zero) * cfg.uv_per_code / 1e6);
    text(12, 67, "触发设置");
    text(13, 67, "%s / %s",
         cfg.trig == 0   ? "自动"
         : cfg.trig == 1 ? "普通"
                         : "单次",
         cfg.edge ? "下降" : "上升");
    text(14, 67, "电平 %u", cfg.level);
    text(15, 67, "滞回 %u", cfg.hyst);
    text(17, 67, "状态诊断");
    text(18, 67, "溢出 %u", scope_read(R_OTR));
    text(19, 67, "丢失 %u", scope_read(R_DROP));
    text(20, 67, "故障 %08lx", (unsigned long)err);
    if (cfg.mode == FFT) {
        text(22, 67, "%u点 %s", cfg.fft_n, cfg.hann ? "汉宁窗" : "矩形窗");
        text(23, 67, "峰 %.1fHz", fft_hz);
        text(24, 67, "%.1f dBFS", fft_db);
    } else if (cfg.mode == EYE) {
        text(22, 67, "%.2f Mb/s", cfg.bitrate / 1e6);
        text(23, 67, "未锁定参考");
        text(24, 67, "抖动 N/A");
    } else {
        text(22, 67, "DDR %s", mem_gate ? "已验证" : "待自检");
        text(23, 67, "分段 %u/8", seg_count);
        text(24, 67, "增益 x%u", 1u << cfg.gain);
    }
    if (cfg.mode == FFT)
        text(27, 1, "FFT:频率 / dBFS | 分辨率 %.2f Hz | 有效采样 %.3f MSa/s",
             cfg.rate / (double)SCOPE_N, (double)cfg.rate * cfg.fft_n / SCOPE_N / 1e6);
    else if (cfg.mode == EYE)
        text(27, 1, "EYE:横轴 0..2 UI | 1 UI = %.2f ns | 未启用时钟恢复", 1e9 / cfg.bitrate);
    else if (cfg.mode == ROLL)
        text(27, 1, "滚动:%.3f ms/列 | 丢失 %u | 采样编号 %llu", 1e8 / cfg.rate, roll_lost,
             (unsigned long long)roll_time);
    else
        text(27, 1, "时间 %.3f us/格 | 视窗 %u 点 | 增益 x%u | 电压%s",
             (cfg.mode == DPX ? SCOPE_N : cfg.span) * 1e5 / cfg.rate, cfg.span, 1u << cfg.gain,
             adc_calibrated ? "已校准" : "标称值");
    if (err)
        text(28, 1, "故障: %08lx 请查看上位机状态 / JTAG 日志", (unsigned long)err);
    else if (sim)
        text(28, 1, "SIM 测试源开启 / 当前不是模拟输入波形");
    else if (valid_record && measurement.max - measurement.min < 16)
        text(28, 1, "未检测到稳定信号 / 输入浮空或近似直流 / 频率 N/A");
    else
        text(28, 1, "采集 %u  密度更新 %u  UI %.1f Hz  丢失 %u", captures_processed, hist_updates,
             frame_hz, drops);
    text(29, 1, "K1 选择  K2 修改  长按反向  双键菜单  双键长按 RUN/STOP");
    if (menu) {
        const char *items[] = {"显示模式",   "运行 / 停止", "实际输入 / SIM", "触发方式",
                               "触发边沿",   "触发电平",    "时间视窗",       "FFT 点数",
                               "FFT 窗函数", "EYE 码率",    "垂直增益",       "零电平位置",
                               "回放起点",   "分段编号",    "长存储采集",     "单次重新触发",
                               "ADC 采样率", "数据编码",    "DDR 自检",       "电压校准系数",
                               "触发滞回"};
        // Two columns keep all 21 items visible at native 16x24 resolution.
        for (unsigned row = 4; row < 23; row++)
            for (unsigned col = 8; col < 63; col++)
                screen[row * 80 + col] = ' ';
        text(4, 9, "设置菜单 / K1 选择 / K2 修改");
        for (unsigned j = 0; j < 21; j++)
            text(6 + j % 11, 9 + (j / 11) * 27, "%c %02u %s", j == selection ? '>' : ' ', j + 1,
                 items[j]);
    }
}

static uint32_t vertical_scale(uint32_t w) {
    if (cfg.mode == FFT || cfg.mode == EYE || cfg.mode == DPX)
        return w;
    int center = 609 - (int)(cfg.zero * 539 / 4095.0);
    int top = 340 + (((int)(w & 1023) - center) * (1 << cfg.gain));
    int bottom = 340 + (((int)(w >> 10) - center) * (1 << cfg.gain));
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
        scope_write(0x20000 + 4 * i, page_dac       ? dac_preview(i)
                                     : valid_record ? vertical_scale(wave[i])
                                                    : 0);
    if (cfg.mode == DPX || cfg.mode == EYE)
        for (i = 0; i < HIST_W * HIST_H; i++)
            scope_write(0x40000 + 4 * i, hist[i]);
    for (i = 0; i < 2400; i++)
        scope_write(0x80000 + 4 * i, screen[i]);
    scope_write(R_OWNER, 1 | (menu << 1) | (selection << 2) |
                             ((page_dac ? 0 : displayed_source_sim()) << 7) | (page_dac << 8));
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
    hits = 0;
    drops = 0;
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
    unsigned previous_y = 609;
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
        unsigned top = (x && previous_y < y) ? previous_y : y;
        unsigned bottom = (x && previous_y > y) ? previous_y : y;
        wave[x] = top | (bottom << 10);
        previous_y = y;
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
    record_source_sim = cfg.sim;
    if (cfg.mode != ROLL)
        valid_record = 1;
    captures_processed++;
    if (!strncmp(message, "MODE CHANGED", 12))
        set_message("LIVE CAPTURE / SOURCE AND STATUS SHOWN ABOVE");
    // Release only AFTER copying the frozen ring. All analysis uses this private snapshot.
    scope_write(R_RELEASE, 1);
    scope_measure(record, SCOPE_N, cfg.rate, &measurement);
    if (auto_scale && cfg.mode == DSO && measurement.max - measurement.min >= 16) {
        cfg.zero = (measurement.max + measurement.min) / 2.0;
        cfg.gain = 0;
        while (cfg.gain < 6 && (measurement.max - measurement.min) * (1u << (cfg.gain + 1)) < 3000)
            cfg.gain++;
        if (measurement.frequency_valid)
            cfg.span = (unsigned)fmin(16384, fmax(64, 3 * cfg.rate / measurement.frequency));
    }
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
        segment_crc[seg] = scope_crc32(record, sizeof(record));
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
    mem_valid = 0;
    mem_gate = 0;
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
    scope_write(R_DMA_START, verify_sim == 2 ? 5 : 1);
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

    if (verify_sim == 2) {
        for (unsigned i = 0; i < DMA_BUFFER_BYTES / 2; i++)
            if (p[i] != (uint16_t)i) {
                reply(0, "code=DDR_STRESS_COMPARE index=%u expected=%u actual=%u", i, (uint16_t)i,
                      p[i]);
                goto fail;
            }
        if (DMA_BUFFER_BYTES / (ms * 1000) < 143.0) {
            reply(0, "code=DDR_BANDWIDTH measured_MBps=%.3f required_MBps=143",
                  DMA_BUFFER_BYTES / (ms * 1000));
            goto fail;
        }
    }
    if (verify_sim == 1) {
        uint32_t phase;
        unsigned bad_index;
        if (!scope_validate_dds(p, DMA_BUFFER_BYTES / 2, 16777, &phase, &bad_index)) {
            reply(0, "code=DMA_SIM_COMPARE index=%u", bad_index);
            goto fail;
        }
    }
    uint32_t crc = scope_crc32(p, DMA_BUFFER_BYTES);
    mem_valid = verify_sim != 2;
    mem_source_sim = cfg.sim;
    mem_first_index = ((uint64_t)scope_read(0xe4) << 32) | scope_read(0xe0);
    reply(1, "dma=PASS bytes=%u time_ms=%.3f payload_MBps=%.3f crc32=%08lx test_kind=%u",
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
    if (!memory_test() || !memory_capture(2) || !memory_capture(1)) {
        mem_gate = 0;
        set_message("SELFTEST FAILED / MEM & SEG DISABLED");
        return;
    }
    mem_gate = 1;
    set_message("DDR HEADROOM + EXACT DMA PASS / ADC VOLTS UNCALIBRATED");
    reply(1, "selftest=PASS rate=%u ddr_headroom=PASS analog=UNCALIBRATED", cfg.rate);
}
static void status(void) {
    static const char *states[]={"IDLE","PREFILL","ARMED","POST","HOLD","FAULT","FAULT","FAULT"};
    reply(
        1,
        "mode=%s run=%u source=%s rate=%u state=%s frame=%u samples=%lu:%08lx otr=%u drop=%u errors=%08lx dead=%u mem_gate=%u irq_lost=%u",
        modes[cfg.mode], cfg.run, cfg.sim ? "SIM" : "ADC", cfg.rate,
        states[(scope_read(R_STATE)>>1)&7], scope_read(R_FRAME),
        (unsigned long)scope_read(R_SAMPLES + 4), (unsigned long)scope_read(R_SAMPLES),
        scope_read(R_OTR), scope_read(R_DROP), (unsigned long)scope_read(R_ERRORS),
        scope_read(R_DEAD), mem_gate, key_lost);
}
static int change_rate(unsigned index) {
    static const unsigned rates[] = {10000000, 25000000, 50000000, 65000000};
    if (index > 3 || !(qualified_rate_mask & (1u << index))) {
        set_message("ADC RATE NOT QUALIFIED BY RELEASE TIMING / HIL");
        return 0;
    }
    if (scope_read(R_DMA_FLAGS) & (1u << 13)) {
        set_message("STOP DMA BEFORE RATE CHANGE");
        return 0;
    }
    unsigned old_run = cfg.run;
    cfg.run = 0;
    if (!apply()) {
        cfg.run = old_run;
        return 0;
    }
    usleep(1000);
    scope_write(R_RATE, index);
    usleep(1000);
    if (scope_read(R_RATE) != rates[index]) {
        cfg.run = old_run;
        set_message("RATE READBACK FAILED");
        return 0;
    }
    cfg.rate = rates[index];
    cfg.run = old_run;
    mem_gate = 0;
    mem_valid = 0;
    seg_count = 0;
    memset(segment_len, 0, sizeof(segment_len));
    valid_record = 0;
    memset(&measurement, 0, sizeof(measurement));
    memset(hist, 0, sizeof(hist));
    roll_sequence = 0;
    roll_columns = 0;
    fft_hz = 0;
    fft_db = -160;
    set_message("RATE CHANGED / RUN SELFTEST TO REQUALIFY DDR");
    return apply();
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
        next = cfg.rate == 10000000 ? 0 : cfg.rate == 25000000 ? 1 : cfg.rate == 50000000 ? 2 : 3;
        change_rate((next + 4 + direction) % 4);
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
    rpc_id = 0;
    if (line[0] == '@') {
        if (strlen(line) < 11 || line[9] != ' ') {
            reply(0, "code=RPC_HEADER");
            return;
        }
        char token[9];
        memcpy(token, line + 1, 8);
        token[8] = 0;
        char *end;
        unsigned long id = strtoul(token, &end, 16);
        if (*end) {
            reply(0, "code=RPC_ID");
            return;
        }
        rpc_id = (uint32_t)id;
        line += 10;
    }
    char *a[8], *p = strtok(line, " ");
    unsigned n = 0;
    while (p && n < 8) {
        a[n++] = p;
        p = strtok(0, " ");
    }
    if (!n)
        return;
    if (dac_command(n, a))
        return;
    if (n == 2 && !strcmp(a[0], "page") && (!strcmp(a[1], "adc") || !strcmp(a[1], "dac"))) {
        page_dac = !strcmp(a[1], "dac");
        menu = 0;
        dirty = 1;
        reply(1, "page=%s", a[1]);
        return;
    }
    if (n == 1 && !strcmp(a[0], "settings")) {
        reply(
            1,
            "mode=%s run=%u source=%s rate=%u span=%u gain=%u zero=%.3f offset=%u segment=%u level=%u hyst=%u edge=%u trig=%u fft_n=%u hann=%u bitrate=%u uv_per_code=%.6f cal_zero=%.3f encoding=%u auto_scale=%u calibrated=%u page=%s",
            modes[cfg.mode], cfg.run, cfg.sim ? "SIM" : "ADC", cfg.rate, cfg.span, cfg.gain,
            cfg.zero, cfg.offset, cfg.segment, cfg.level, cfg.hyst, cfg.edge, cfg.trig, cfg.fft_n,
            cfg.hann, cfg.bitrate, cfg.uv_per_code, cfg.cal_zero, cfg.encoding, auto_scale,
            adc_calibrated, page_dac ? "DAC" : "ADC");
        return;
    }
    if (n == 3 && !strcmp(a[0], "view")) {
        double v;
        if (!number(a[2], &v))
            goto bad;
        if (!strcmp(a[1], "auto") && (v == 0 || v == 1))
            auto_scale = (unsigned)v;
        else if (!strcmp(a[1], "span") && v >= 64 && v <= 16384 && v == (unsigned)v)
            cfg.span = (unsigned)v;
        else if (!strcmp(a[1], "gain") && v >= 0 && v <= 6 && v == (unsigned)v)
            cfg.gain = (unsigned)v;
        else if (!strcmp(a[1], "zero") && v >= 0 && v <= 4095)
            cfg.zero = v;
        else if (!strcmp(a[1], "offset") && v >= 0 && v <= 1048575 && v == (unsigned)v)
            cfg.offset = (unsigned)v;
        else if (!strcmp(a[1], "segment") && v >= 0 && v < 8 && v == (unsigned)v)
            cfg.segment = (unsigned)v;
        else if (!strcmp(a[1], "hyst") && v >= 0 && v <= 255 && v == (unsigned)v) {
            cfg.hyst = (unsigned)v;
            apply();
        } else
            goto bad;
        dirty = 1;
        reply(1, "view_%s=%.3f", a[1], v);
        return;
    }
    if (n == 1 && !strcmp(a[0], "autoscale")) {
        if (!valid_record) {
            reply(0, "code=NO_CAPTURE");
            return;
        }
        cfg.zero = (measurement.max + measurement.min) / 2.0;
        cfg.gain = 0;
        while (cfg.gain < 6 && (measurement.max - measurement.min) * (1u << (cfg.gain + 1)) < 3000)
            cfg.gain++;
        if (measurement.frequency_valid) {
            double span = 3 * cfg.rate / measurement.frequency;
            cfg.span = (unsigned)fmin(16384, fmax(64, span));
        }
        dirty = 1;
        reply(1, "autoscale span=%u gain=%u zero=%.3f", cfg.span, cfg.gain, cfg.zero);
        return;
    }
    if (n == 1 && !strcmp(a[0], "rearm")) {
        reply(apply(), "rearmed");
        return;
    }
    if (n == 1 && !strcmp(a[0], "uart")) {
        reply(1, "uart_rx_lost=%u baud=115200 rpc=1", uart_lost);
        return;
    }
    if (!strcmp(a[0], "help")) {
        reply(
            1,
            "help ver selftest status measure clocks capture trigger dma dpx errors mode run menu trig adc fft eye cal memory config video");
        return;
    }
    if (!strcmp(a[0], "ver")) {
        reply(
            1,
            "product=Z7_SCOPE fw=4.0 rtl=%08lx source_sha=%08lx fw_sha=%08lx id=%08lx SDK=2018.3 qualification=BENCH_PENDING",
            (unsigned long)scope_read(R_VER), (unsigned long)scope_read(0xf4),
            (unsigned long)SCOPE_FW_SHA, (unsigned long)scope_read(R_ID));
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
    if (!strcmp(a[0], "measure")) {
        reply(
            1,
            "valid=%u source=%s min=%u max=%u mean=%.4f rms_code=%.4f frequency=%.4f frequency_valid=%u overrange=%u calibrated=%u",
            valid_record, displayed_source_sim() ? "SIM" : "ADC", measurement.min, measurement.max,
            measurement.mean, measurement.rms, measurement.frequency, measurement.frequency_valid,
            measurement.overrange, adc_calibrated);
        return;
    }
    if (!strcmp(a[0], "segments")) {
        for (unsigned i = 0; i < SEGMENTS; i++) {
            const uint16_t *p = (const uint16_t *)(uintptr_t)(SEG_BUFFER + i * SCOPE_N * 2);
            unsigned crc_ok = 0, sequence_ok = 0;
            if (segment_len[i]) {
                Xil_DCacheInvalidateRange((UINTPTR)p, segment_len[i] * 2);
                crc_ok = scope_crc32(p, segment_len[i] * 2) == segment_crc[i];
                if (segment_sim[i]) {
                    uint32_t phase;
                    unsigned bad;
                    sequence_ok = scope_validate_dds(p, segment_len[i], 16777, &phase, &bad);
                }
            }
            reply(!segment_len[i] || (crc_ok && (!segment_sim[i] || sequence_ok)),
                  "segment=%u length=%u first=%llu source=%s crc32=%08lx crc_ok=%u sequence_ok=%u",
                  i, segment_len[i], (unsigned long long)segment_time[i],
                  segment_sim[i] ? "SIM" : "ADC", (unsigned long)segment_crc[i], crc_ok,
                  sequence_ok);
        }
        return;
    }
    if (!strcmp(a[0], "video")) {
        reply(1, "frame=%u pixel_crc32=%08lx asset_crc32=%08lx", scope_read(R_FRAME),
              (unsigned long)scope_read(0xf8), (unsigned long)scope_read(R_CRC));
        return;
    }
    if (n == 2 && !strcmp(a[0], "memory") && !strcmp(a[1], "bandwidth")) {
        memory_capture(2);
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
            set_message(cfg.sim ? "SIM TEST SOURCE ACTIVE"
                                : "REAL ADC ACTIVE / VOLTAGE CALIBRATION REQUIRED");
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
            reply(change_rate(index), "rate=%u mem_gate=%u", cfg.rate, mem_gate);
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
        adc_calibrated = 1;
        cfg.zero = zero;
        cfg.cal_zero = zero;
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
        if (!strcmp(a[1], "save")) {
            saved = cfg;
            saved_calibrated=adc_calibrated;
            saved_auto_scale=auto_scale;
        } else if (!strcmp(a[1], "load")) {
            if (!saved.rate) {
                reply(0, "code=NO_SAVED_CONFIG");
                return;
            }
            if (saved.mode >= MEM && !mem_gate) {
                reply(0, "code=DDR_GATE_CLOSED");
                return;
            }
            unsigned saved_index = saved.rate == 10000000   ? 0
                                   : saved.rate == 25000000 ? 1
                                   : saved.rate == 50000000 ? 2
                                                            : 3;
            if (saved.rate != cfg.rate && !change_rate(saved_index)) {
                reply(0, "code=CONFIG_RATE_RESTORE");
                return;
            }
            cfg = saved;
            adc_calibrated=saved_calibrated;
            auto_scale=saved_auto_scale;
            apply();
        } else
            goto bad;
        reply(1, "config=%s storage=VOLATILE_RAM", a[1]);
        return;
    }
bad:
    reply(0, "code=INVALID_COMMAND_OR_ARGUMENT use=help");
}

static void poll_debug(void) {
    volatile scope_debug_mailbox *m = DEBUG_MAILBOX;
    uint32_t req = m->request;
    if (req == m->done)
        return;
    debug_barrier();
    char cmd[160];
    for (unsigned i = 0; i < 159; i++)
        cmd[i] = m->command[i];
    cmd[159] = 0;
    m->length = 0;
    m->flags = 0;
    m->response[0] = 0;
    debug_reply_active = 1;
    dispatch(cmd);
    debug_reply_active = 0;
    debug_barrier();
    m->done = req;
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
    while (uart_tail != uart_head) {
        unsigned ch = uart_rx[uart_tail];
        uart_tail = (uart_tail + 1) & 1023;
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
static int uart_init(void) {
    static XUartPs uart;
    XUartPs_Config *uc = XUartPs_LookupConfig(XPAR_XUARTPS_0_DEVICE_ID);
    if (!uc || XUartPs_CfgInitialize(&uart, uc, uc->BaseAddress) != XST_SUCCESS)
        return 0;
    return XUartPs_SetBaudRate(&uart, 115200) == XST_SUCCESS;
}
int main(void) {
    Xil_ICacheEnable();
    Xil_DCacheEnable();
    debug_init();
    if (!uart_init())
        return 1;
    printf("\r\nZ7_SCOPE BOOT fw=4.0 SDK=2018.3 DDR DMA reserved 0x10000000..0x105FFFFF\r\n");
    DEBUG_MAILBOX->stage = 2;
    if (scope_read(R_ID) != 0x53434f50) {
        printf("ERR code=PL_ID_MISMATCH\r\n");
        return 1;
    }
    DEBUG_MAILBOX->stage = 3;
    if (!interrupts_init())
        printf("ERR code=GIC_INIT\r\n");
    DEBUG_MAILBOX->stage = 4;
    uint64_t startup = now();
    while (scope_read(0x80) != 0) {
        if (elapsed_ms(startup) > 100) {
            DEBUG_MAILBOX->stage = 0xe004;
            break;
        }
    }
    DEBUG_MAILBOX->stage = 5;
    if (!dac_generate(0, 1000, 0.1, 0.5, 0.5, 0))
        reply(0, "code=DAC_INIT");
    scope_write(R_OWNER, 1);
    apply();
    last_render = now();
    DEBUG_MAILBOX->stage = 6;
    for (;;) {
        DEBUG_MAILBOX->heartbeat++;
        poll_debug();
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
