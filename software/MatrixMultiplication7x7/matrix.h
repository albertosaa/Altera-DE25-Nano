#ifndef MATRIX7_H
#define MATRIX7_H
#include <stdint.h>

enum { MATRIX_N = 7, MATRIX_ELEMENTS = 49 };
/* A e B: inteiros com sinal de 16 bits em ordem de linhas.
 * Sete produtos exigem até 35 bits (largura conservadora); C usa 64 bits.
 * Esta função está em outro .c para impedir que o benchmark, compilado
 * SEM LTO, elimine ou retire multiplicações repetidas de dentro do laço. */
void multiply_cpu(const int16_t a[49], const int16_t b[49], int64_t c[49]);
void multiply_reference(const int16_t a[49], const int16_t b[49], int64_t c[49]);
#endif
