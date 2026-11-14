#ifndef MATRIX_H
#define MATRIX_H

#include <stdint.h>

/* Matrizes em ordem de linhas: [a00, a01, a10, a11].
 * Cada entrada tem 16 bits com sinal. A soma de dois produtos precisa
 * de 33 bits; int64_t preserva inclusive o caso -32768 * -32768. */
static inline void multiply_cpu(const int16_t a[4], const int16_t b[4],
                                int64_t c[4])
{
    unsigned i, j, k;
    for (i = 0; i < 2; ++i) {
        for (j = 0; j < 2; ++j) {
            c[2 * i + j] = 0;
            for (k = 0; k < 2; ++k)
                c[2 * i + j] += (int64_t)a[2 * i + k] * b[2 * k + j];
        }
    }
}
#endif
