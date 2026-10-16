#ifndef SCOPE_ANALYSIS_H
#define SCOPE_ANALYSIS_H
#include <stdint.h>
#define SCOPE_N 16384
#define SCOPE_W 960
#define HIST_W 160
#define HIST_H 90
typedef struct {
    double mean, rms, frequency;
    uint16_t min, max;
    uint32_t crossings, overrange;
    int frequency_valid;
} scope_measurements;
void scope_measure(const uint16_t *data, unsigned n, double fs, scope_measurements *out);
void scope_envelope(const uint16_t *data, unsigned n, unsigned start, unsigned length,
                    uint32_t wave[SCOPE_W]);
void scope_fft(const uint16_t *data, unsigned n, unsigned stride, int hann, double fs, float *re,
               float *im, float *db, double *peak_hz, double *peak_db);
void scope_set_point_sink(void (*sink)(unsigned, unsigned));
void scope_set_hit_sink(void (*sink)(unsigned));
void scope_density(uint8_t *hist, const uint16_t *data, unsigned n, unsigned rate, unsigned bitrate,
                   int eye, uint64_t first_index, unsigned limit, uint32_t *hits,
                   uint32_t *dropped);
int scope_validate_dds(const uint16_t *data, unsigned n, uint32_t step, uint32_t *phase,
                       unsigned *bad_index);
uint32_t scope_crc32(const void *data, unsigned bytes);
#endif
