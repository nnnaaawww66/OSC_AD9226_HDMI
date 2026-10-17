/* Dedicated DAC state. No ADC configuration or capture writes here. */
#define DAC_N 2048
#define DAC_FS 50000000u
static uint16_t dac_table[DAC_N], dac_staging[DAC_N];
static unsigned dac_on, dac_uploaded, dac_shape, page_dac;
static double dac_frequency = 1000, dac_amplitude = 0.1, dac_offset = 0.5, dac_duty = 0.5;
static uint32_t dac_crc;
static const char *dac_names[] = {"sine", "square", "triangle", "saw", "dc", "custom"};
static int number(const char *s, double *v) {
    char *end;
    *v = strtod(s, &end);
    return s != end && !*end && isfinite(*v);
}
static int dac_apply_table(const uint16_t *table, double frequency, unsigned on) {
    if (!wait_idle(0x108, 1, 100))
        return 0;
    for (unsigned i = 0; i < DAC_N; i++)
        scope_write(0x30000 + i * 4, table[i]);
    for (unsigned i = 0; i < DAC_N; i++)
        if (scope_read(0x30000 + i * 4) != table[i])
            return 0;
    uint32_t step = (uint32_t)llround(frequency * 4294967296.0 / DAC_FS);
    scope_write(0x100, step);
    scope_write(0x104, (on << 14) | 8192);
    scope_write(0x108, 1);
    if (!wait_idle(0x108, 1, 100))
        return 0;
    memcpy(dac_table, table, sizeof(dac_table));
    dac_frequency = step * (double)DAC_FS / 4294967296.0;
    dac_on = on;
    dac_crc = scope_crc32(dac_table, sizeof(dac_table));
    dirty = 1;
    return 1;
}
static int dac_generate(unsigned shape, double frequency, double amp, double offset, double duty,
                        unsigned on) {
    if (!isfinite(frequency) || !isfinite(amp) || !isfinite(offset) || !isfinite(duty) ||
        shape > 4 || frequency < 0.1 || frequency > 5000000 || amp < 0 || amp > 1.0 || offset < 0 ||
        offset > 1 || offset - amp / 2 < 0 || offset + amp / 2 > 1 || duty < 0.01 || duty > 0.99)
        return 0;
    for (unsigned i = 0; i < DAC_N; i++) {
        double t = i / (double)DAC_N, v = 0;
        if (shape == 0)
            v = sin(6.283185307179586 * t);
        if (shape == 1)
            v = t < duty ? 1 : -1;
        if (shape == 2)
            v = t < duty ? -1 + 2 * t / duty : 1 - 2 * (t - duty) / (1 - duty);
        if (shape == 3)
            v = 2 * t - 1;
        dac_staging[i] = (uint16_t)lround(16383 * (offset + amp * 0.5 * v));
    }
    if (!dac_apply_table(dac_staging, frequency, on))
        return 0;
    dac_shape = shape;
    dac_amplitude = amp;
    dac_offset = offset;
    dac_duty = duty;
    return 1;
}
static void dac_status_reply(void) {
    uint32_t cycles = scope_read(0x10c), phase = 0, pins = 0;
    if (scope_read(R_VER) >= 0x00040000) {
        phase = scope_read(0x114);
        pins = scope_read(0x118);
    }
    reply(
        1,
        "page=%s dac_enabled=%u shape=%s fs=%u actual_hz=%.9f amplitude_fs=%.6f offset_fs=%.6f duty=%.6f table_crc=%08lx cycles=%u phase=%08lx sample_code=%u hw_enabled=%u busy=%u voltage_calibrated=0 amplitude_limit_fs=1.0",
        page_dac ? "DAC" : "ADC", dac_on, dac_names[dac_shape], DAC_FS, dac_frequency,
        dac_amplitude, dac_offset, dac_duty, (unsigned long)dac_crc, cycles, (unsigned long)phase,
        (pins >> 2) & 16383, (pins >> 1) & 1, scope_read(0x108) & 1);
}
static int dac_command(unsigned n, char **a) {
    if (strcmp(a[0], "dac"))
        return 0;
    if (n == 2 && !strcmp(a[1], "status")) {
        dac_status_reply();
        return 1;
    }
    if (n == 3 && !strcmp(a[1], "enable") && (!strcmp(a[2], "0") || !strcmp(a[2], "1"))) {
        reply(dac_apply_table(dac_table, dac_frequency, atoi(a[2])), "dac_enable=%s", a[2]);
        return 1;
    }
    if (n == 8 && !strcmp(a[1], "set")) {
        unsigned shape;
        double f, amp, offset, duty, on;
        for (shape = 0; shape < 5; shape++)
            if (!strcmp(a[2], dac_names[shape]))
                break;
        if (number(a[3], &f) && number(a[4], &amp) && number(a[5], &offset) &&
            number(a[6], &duty) && number(a[7], &on) && (on == 0 || on == 1)) {
            int ok = dac_generate(shape, f, amp, offset, duty, (unsigned)on);
            reply(ok, "dac_set=%s actual_hz=%.9f crc=%08lx limit_fs=1.0",
                  ok ? "APPLIED" : "REJECTED", dac_frequency, (unsigned long)dac_crc);
            return 1;
        }
    }
    if (n == 2 && !strcmp(a[1], "begin")) {
        dac_uploaded = 0;
        reply(1, "dac_upload_begin count=2048");
        return 1;
    }
    if (n == 4 && !strcmp(a[1], "chunk")) {
        double at;
        unsigned len = strlen(a[3]);
        if (!number(a[2], &at) || at != dac_uploaded || len == 0 || len % 4 || len > 96 ||
            dac_uploaded + len / 4 > DAC_N)
            goto invalid_dac;
        uint16_t part[24];
        for (unsigned i = 0; i < len / 4; i++) {
            unsigned value = 0;
            for (unsigned j = 0; j < 4; j++) {
                char c = a[3][4 * i + j];
                unsigned v;
                if (c >= '0' && c <= '9')
                    v = c - '0';
                else if (c >= 'a' && c <= 'f')
                    v = c - 'a' + 10;
                else if (c >= 'A' && c <= 'F')
                    v = c - 'A' + 10;
                else
                    goto invalid_dac;
                value = value * 16 + v;
            }
            // All tables are validated before any active-bank commit.
            if (value > 16383)
                goto invalid_dac;
            part[i] = value;
        }
        memcpy(dac_staging + dac_uploaded, part, len / 4 * sizeof(uint16_t));
        dac_uploaded += len / 4;
        reply(1, "dac_uploaded=%u", dac_uploaded);
        return 1;
    }
    if (n == 5 && !strcmp(a[1], "commit")) {
        char *end;
        unsigned long crc = strtoul(a[2], &end, 16);
        double f, on;
        if (*end || dac_uploaded != DAC_N || crc != scope_crc32(dac_staging, sizeof(dac_staging)) ||
            !number(a[3], &f) || !number(a[4], &on) || f < 0.1 || f > 5000000 ||
            (on != 0 && on != 1))
            goto invalid_dac;
        if (!dac_apply_table(dac_staging, f, (unsigned)on)) {
            reply(0, "code=DAC_READBACK_OR_ACK");
            return 1;
        }
        dac_shape = 5;
        unsigned lo = 16383, hi = 0;
        for (unsigned i = 0; i < DAC_N; i++) {
            if (dac_table[i] < lo)
                lo = dac_table[i];
            if (dac_table[i] > hi)
                hi = dac_table[i];
        }
        dac_amplitude = (hi - lo) / 16383.0;
        dac_offset = (hi + lo) / (2 * 16383.0);
        dac_duty = 0.5;
        reply(1, "dac_commit=APPLIED crc=%08lx actual_hz=%.9f", (unsigned long)dac_crc,
              dac_frequency);
        return 1;
    }
invalid_dac:
    reply(0, "code=DAC_ARGUMENT_OR_UPLOAD_CRC limit=14bit_FS voltage=UNCALIBRATED");
    return 1;
}
