#define _POSIX_C_SOURCE 200809L
#define _FILE_OFFSET_BITS 64

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include "matrix.h"

/* Estes deslocamentos, em BYTES, devem coincidir com o módulo Verilog. */
enum { CONTROL = 0x00, STATUS = 0x04, A = 0x10, B = 0x20,
       C = 0x30, ID = 0x50, SPAN = 0x80 };
#define EXPECTED_ID UINT32_C(0x4d4d0001)

/* Somente esta camada depende do Linux. O cálculo em matrix.h usa C padrão.
 * /dev/mem exige privilégios e uma ponte HPS/FPGA já configurada e habilitada.
 * volatile impede eliminar os acessos. Em AArch64, dmb ordena o MMIO;
 * volatile sozinho não é uma barreira de hardware. */
static void barrier(void)
{
#if defined(__aarch64__)
    __asm__ volatile ("dmb sy" ::: "memory");
#endif
}

static uint32_t read_reg(volatile uint32_t *regs, unsigned offset)
{
    uint32_t value;
    barrier();
    value = regs[offset / 4];
    barrier();
    return value;
}

static void write_reg(volatile uint32_t *regs, unsigned offset, uint32_t value)
{
    barrier();
    regs[offset / 4] = value;
    barrier();
}

static void print_matrix(const char *name, const int64_t c[4])
{
    printf("%s:\n[ %" PRId64 "  %" PRId64 " ]\n[ %" PRId64 "  %" PRId64 " ]\n",
           name, c[0], c[1], c[2], c[3]);
}

int main(int argc, char **argv)
{
    const int16_t a[4] = {1, 2, 3, 4};
    const int16_t b[4] = {5, 6, 7, 8};
    int64_t cpu[4], fpga[4];
    volatile uint32_t *regs;
    void *mapping;
    uint64_t base, page_base;
    size_t delta, length;
    long page_size;
    char *end;
    int fd, result = EXIT_FAILURE;
    unsigned i;
    struct timespec start, now;

    multiply_cpu(a, b, cpu);
    puts("A = [[1, 2], [3, 4]]; B = [[5, 6], [7, 8]]");
    print_matrix("Resultado no ARM", cpu);

    if (argc == 2 && strcmp(argv[1], "--cpu-only") == 0) {
        /* Diagnóstico do C: não simula nem valida comunicação com a FPGA. */
        return (cpu[0] == 19 && cpu[1] == 22 && cpu[2] == 43 && cpu[3] == 50)
               ? EXIT_SUCCESS : EXIT_FAILURE;
    }
    if (argc != 2 || argv[1][0] == '-') {
        fprintf(stderr, "Uso: %s ENDERECO_FISICO | --cpu-only\n", argv[0]);
        return EXIT_FAILURE;
    }
    errno = 0;
    base = strtoull(argv[1], &end, 0);
    if (errno || end == argv[1] || *end || base > INT64_MAX - SPAN || base % 4) {
        fprintf(stderr, "Endereço inválido: use uma base física alinhada a 4 bytes.\n");
        return EXIT_FAILURE;
    }
    page_size = sysconf(_SC_PAGESIZE);
    if (page_size <= 0) {
        fprintf(stderr, "Não foi possível consultar o tamanho de página.\n");
        return EXIT_FAILURE;
    }
    page_base = base / (uint64_t)page_size * (uint64_t)page_size;
    delta = (size_t)(base - page_base);
    length = delta + SPAN;
    fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("open /dev/mem");
        return EXIT_FAILURE;
    }
    mapping = mmap(NULL, length, PROT_READ | PROT_WRITE, MAP_SHARED, fd,
                   (off_t)page_base);
    if (mapping == MAP_FAILED) {
        perror("mmap");
        close(fd);
        return EXIT_FAILURE;
    }
    regs = (volatile uint32_t *)((unsigned char *)mapping + delta);
    if (read_reg(regs, ID) != EXPECTED_ID) {
        fprintf(stderr, "ID incompatível: confira o bitstream e o mapa de endereços.\n");
        goto cleanup;
    }
    /* Limpa DONE anterior, carrega as oito entradas e inicia um novo cálculo. */
    write_reg(regs, CONTROL, 0);
    for (i = 0; i < 4; ++i) {
        write_reg(regs, A + 4 * i, (uint16_t)a[i]);
        write_reg(regs, B + 4 * i, (uint16_t)b[i]);
    }
    if (clock_gettime(CLOCK_MONOTONIC, &start) != 0) {
        perror("clock_gettime");
        goto cleanup;
    }
    write_reg(regs, CONTROL, 1);
    while (!(read_reg(regs, STATUS) & 1)) {
        if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
            perror("clock_gettime");
            goto cleanup;
        }
        if (now.tv_sec - start.tv_sec > 1) {
            fprintf(stderr, "Timeout aguardando DONE da FPGA.\n");
            goto cleanup;
        }
    }
    for (i = 0; i < 4; ++i) {
        uint32_t low = read_reg(regs, C + 8 * i);
        uint32_t high = read_reg(regs, C + 8 * i + 4);
        /* Parte alta vale 0 ou -1: reconstrução com sinal sem conversão
         * de uint64_t fora da faixa de int64_t. Resultados ficam estáveis
         * até o próximo START ou reset, portanto as duas leituras são seguras. */
        fpga[i] = (high == UINT32_MAX ? -INT64_C(4294967296) : 0) + low;
        if (high != 0 && high != UINT32_MAX) {
            fprintf(stderr, "Parte alta inválida no resultado %u.\n", i);
            goto cleanup;
        }
    }
    print_matrix("Resultado na FPGA", fpga);
    result = EXIT_SUCCESS;
    for (i = 0; i < 4; ++i)
        if (cpu[i] != fpga[i]) result = EXIT_FAILURE;
    puts(result == EXIT_SUCCESS ? "SUCESSO: ARM e FPGA concordam." : "FALHA: resultados diferentes.");
cleanup:
    munmap(mapping, length);
    close(fd);
    return result;
}
