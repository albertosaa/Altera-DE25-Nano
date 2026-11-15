#include <stdio.h>
#include <stdlib.h>
#include "matrix.h"

int main(void)
{
    int16_t a[49], b[49];
    int64_t c[49], reference[49];
    uint32_t state = 12345;
    unsigned test, i;
    for (test = 0; test < 104; ++test) {
        for (i = 0; i < 49; ++i) {
            state = state * UINT32_C(1664525) + UINT32_C(1013904223);
            a[i] = (int16_t)((int32_t)(state >> 16) - 32768);
            state = state * UINT32_C(1664525) + UINT32_C(1013904223);
            b[i] = (int16_t)((int32_t)(state >> 16) - 32768);
            if (test == 0) a[i] = b[i] = 0;
            if (test == 1) a[i] = b[i] = -32768;
            if (test == 2) { a[i] = -32768; b[i] = 32767; }
            if (test == 3) a[i] = b[i] = (i / 7 == i % 7);
        }
        multiply_cpu(a, b, c);
        multiply_reference(a, b, reference);
        for (i = 0; i < 49; ++i) {
            if (c[i] != reference[i]) return EXIT_FAILURE;
            if (test == 1 && c[i] != INT64_C(7516192768)) return EXIT_FAILURE;
            if (test == 2 && c[i] != -INT64_C(7515963392)) return EXIT_FAILURE;
            if (test == 3 && c[i] != (i / 7 == i % 7)) return EXIT_FAILURE;
        }
    }
    puts("C: 104 pares 7x7 corretos, incluindo limites além de 32 bits.");
    return EXIT_SUCCESS;
}
