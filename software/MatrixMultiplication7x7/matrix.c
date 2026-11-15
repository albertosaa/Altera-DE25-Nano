#include "matrix.h"

/* Ordem i-k-j: B e C são percorridas sequencialmente na dimensão interna.
 * Sem bibliotecas externas e sem dependência de instruções específicas ARM.
 * O compilador pode otimizar/vetorizar este código com -O3. */
void multiply_cpu(const int16_t a[49], const int16_t b[49], int64_t c[49])
{
    unsigned i, j, k;
    for (i = 0; i < 49; ++i) c[i] = 0;
    for (i = 0; i < 7; ++i)
        for (k = 0; k < 7; ++k)
            for (j = 0; j < 7; ++j)
                c[7*i+j] += (int64_t)a[7*i+k] * b[7*k+j];
}

/* Referência independente da ordem do benchmark: um produto escalar por Cij.
 * É usada somente na verificação, nunca na região cronometrada. */
void multiply_reference(const int16_t a[49], const int16_t b[49], int64_t c[49])
{
    unsigned i, j, k;
    for (i = 0; i < 7; ++i)
        for (j = 0; j < 7; ++j) {
            int64_t sum = 0;
            for (k = 0; k < 7; ++k)
                sum += (int64_t)a[7*i+k] * b[7*k+j];
            c[7*i+j] = sum;
        }
}
