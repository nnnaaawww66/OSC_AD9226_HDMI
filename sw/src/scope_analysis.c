#include "scope_analysis.h"
#include <string.h>
#include <math.h>
#include <stdlib.h>
#define PI 3.14159265358979323846
static unsigned clamp(unsigned x, unsigned hi) { return x > hi ? hi : x; }
uint32_t scope_crc32(const void *src, unsigned n) {
    const uint8_t *p = src;
    uint32_t c = ~0u;
    unsigned k;
    while (n--) {
        c ^= *p++;
        for (k = 0; k < 8; k++)
            c = (c >> 1) ^ (0xedb88320u & -(c & 1));
    }
    return ~c;
}
void scope_measure(const uint16_t *d, unsigned n, double fs, scope_measurements *o) {
    unsigned i;
    uint64_t sum = 0, sumsq = 0;
    double first = 0, last = 0;
    int armed = 0;
    memset(o, 0, sizeof(*o));
    o->min = 4095;
    if (!n)
        return;
    for (i = 0; i < n; i++) {
        unsigned v = d[i] & 4095;
        sum += v;
        sumsq += (uint64_t)v * v;
        if (v < o->min)
            o->min = v;
        if (v > o->max)
            o->max = v;
        if (d[i] & 4096)
            o->overrange++;
    }
    o->mean = (double)sum / n;
    o->rms = sqrt((double)sumsq / n);
    double level = (o->min + o->max) * 0.5, hyst = (o->max - o->min) * 0.02;
    if (o->max - o->min < 16 || o->overrange)
        return;
    for (i = 1; i < n; i++) {
        double prev = d[i - 1] & 4095, cur = d[i] & 4095;
        if (cur < level - hyst)
            armed = 1;
        if (armed && prev < level && cur >= level) {
            double t = i - 1 + (level - prev) / (cur - prev);
            if (!o->crossings)
                first = t;
            last = t;
            o->crossings++;
            armed = 0;
        }
    }
    if (o->crossings >= 2 && last > first) {
        o->frequency = fs * (o->crossings - 1) / (last - first);
        o->frequency_valid = 1;
    }
}
void scope_envelope(const uint16_t *d, unsigned n, unsigned start, unsigned length, uint32_t *w) {
    unsigned x, i;
    length = clamp(length, n - start);
    for (x = 0; x < SCOPE_W; x++) {
        unsigned a = start + (uint64_t)x * length / SCOPE_W,
                 b = start + (uint64_t)(x + 1) * length / SCOPE_W;
        unsigned lo = 4095, hi = 0;
        if (b <= a)
            b = a + 1;
        if (b > n)
            b = n;
        for (i = a; i < b; i++) {
            unsigned v = d[i] & 4095;
            if (v < lo)
                lo = v;
            if (v > hi)
                hi = v;
        }
        unsigned top = 609 - hi * 539 / 4095, bottom = 609 - lo * 539 / 4095;
        w[x] = top | (bottom << 10);
    }
}
void scope_fft(const uint16_t *d, unsigned n, unsigned stride, int hann, double fs, float *re,
               float *im, float *db, double *peak_hz, double *peak_db) {
    unsigned i, j, k, len;
    double avg = 0, gain = 0, max_amp = 0;
    unsigned peak = 1;
    for (i = 0; i < n * stride; i++) {
        avg += d[i] & 4095;
    }
    avg /= (n * stride);
    for (i = 0; i < n; i++) {
        double w = hann ? 0.5 - 0.5 * cos(2 * PI * i / (n - 1)) : 1.0;
        gain += w;
        double value = 0;
        for (j = 0; j < stride; j++) {
            value += d[i * stride + j] & 4095;
        }
        value /= stride;
        re[i] = (float)((value - avg) * w);
        im[i] = 0;
    }
    for (i = 1, j = 0; i < n; i++) {
        unsigned bit = n >> 1;
        for (; j & bit; bit >>= 1)
            j ^= bit;
        j ^= bit;
        if (i < j) {
            float t = re[i];
            re[i] = re[j];
            re[j] = t;
        }
    }
    for (len = 2; len <= n; len <<= 1) {
        double angle = -2 * PI / len;
        float wr = (float)cos(angle), wi = (float)sin(angle);
        for (i = 0; i < n; i += len) {
            float ur = 1, ui = 0;
            for (j = 0; j < len / 2; j++) {
                k = i + j;
                unsigned q = k + len / 2;
                float tr = ur * re[q] - ui * im[q], ti = ur * im[q] + ui * re[q];
                re[q] = re[k] - tr;
                im[q] = im[k] - ti;
                re[k] += tr;
                im[k] += ti;
                float nr = ur * wr - ui * wi;
                ui = ur * wi + ui * wr;
                ur = nr;
            }
        }
    }
    for (i = 0; i < n / 2; i++) {
        double amp = hypot(re[i], im[i]) * 2 / (gain * 2048.0);
        if (i == 0)
            amp *= 0.5;
        db[i] = (float)(20 * log10(amp > 1e-6 ? amp : 1e-6));
        if (i > 0 && amp > max_amp) {
            max_amp = amp;
            peak = i;
        }
    }
    double correction = 0;
    if (peak > 1 && peak < n / 2 - 1) {
        double a = db[peak - 1], b = db[peak], c = db[peak + 1], den = a - 2 * b + c;
        if (fabs(den) > 1e-6)
            correction = 0.5 * (a - c) / den;
        if (fabs(correction) > 0.5)
            correction = 0;
    }
    *peak_hz = (peak + correction) * (fs / stride) / n;
    *peak_db = db[peak];
}
static void (*point_sink)(unsigned, unsigned) = 0;
void scope_set_point_sink(void (*sink)(unsigned, unsigned)) { point_sink = sink; }
static void (*hit_sink)(unsigned) = 0;
void scope_set_hit_sink(void (*sink)(unsigned)) { hit_sink = sink; }
static void hit(uint8_t *h, unsigned x, unsigned y, unsigned limit, uint32_t *hits,
                uint32_t *drop) {
    if (*hits >= limit) {
        (*drop)++;
        return;
    }
    unsigned a = y * HIST_W + x;
    if (hit_sink)
        hit_sink(a);
    else if (h[a] < 255)
        h[a]++;
    (*hits)++;
}
void scope_density(uint8_t *h, const uint16_t *d, unsigned n, unsigned rate, unsigned bitrate,
                   int eye, uint64_t first, unsigned limit, uint32_t *hits, uint32_t *drop) {
    unsigned i;
    int px = -1, py = 0;
    *hits = 0;
    *drop = 0;
    if (!hit_sink && !point_sink) {
        for (i = 0; i < HIST_W * HIST_H; i++)
            h[i] = h[i] > 1 ? h[i] - 1 : 0;
    }
    for (i = 0; i < n; i += 4) {
        unsigned x = eye ? (unsigned)((((first + i) * bitrate) % ((uint64_t)2 * rate)) * HIST_W /
                                      ((uint64_t)2 * rate))
                         : (uint64_t)i * HIST_W / n;
        int y = (4095 - (d[i] & 4095)) * (HIST_H - 1) / 4095;
        if (point_sink) {
            unsigned steps = 1;
            if (px >= 0 && x >= (unsigned)px && x - (unsigned)px <= 80) {
                unsigned dx = x - px, dy = abs(y - py);
                steps = dx > dy ? dx : dy;
                if (!steps)
                    steps = 1;
            }
            if (*hits + steps <= limit) {
                point_sink(x, y);
                *hits += steps;
            } else
                *drop += steps;
            px = x;
            py = y;
            continue;
        }

        if (px >= 0 && x >= (unsigned)px && x - (unsigned)px <= 4) {
            int dx = (int)x - px, dy = abs(y - py), steps = dx > dy ? dx : dy;
            if (!steps)
                steps = 1;
            int j;
            for (j = 1; j <= steps; j++)
                hit(h, px + dx * j / steps, py + (y - py) * j / steps, limit, hits, drop);
        } else
            hit(h, x, y, limit, hits, drop);
        px = x;
        py = y;
    }
}

static unsigned dds_code(uint32_t phase) {
    phase &= 0xffffff;
    return (phase & 0x800000) ? 4095 - ((phase >> 11) & 4095) : ((phase >> 11) & 4095);
}
int scope_validate_dds(const uint16_t *data, unsigned n, uint32_t step, uint32_t *phase,
                       unsigned *bad_index) {
    if (n < 2048) {
        *bad_index = 0;
        return 0;
    }
    for (unsigned sign = 0; sign < 2; sign++)
        for (unsigned low = 0; low < 2048; low++) {
            uint32_t ph =
                (sign << 23) | ((sign ? 4095 - (data[0] & 4095) : (data[0] & 4095)) << 11) | low;
            unsigned j;
            /* Full fractional period disambiguates initial phases sharing a short quantized prefix.
             */
            for (j = 0; j < 2048; j++)
                if (data[j] != dds_code(ph + step * j))
                    break;
            if (j != 2048)
                continue;
            *phase = ph;
            for (j = 2048; j < n; j++)
                if (data[j] != dds_code(ph + step * j)) {
                    *bad_index = j;
                    return 0;
                }
            *bad_index = n;
            return 1;
        }
    *bad_index = 0;
    return 0;
}
