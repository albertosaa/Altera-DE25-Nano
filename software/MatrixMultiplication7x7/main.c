#define _GNU_SOURCE
#define _FILE_OFFSET_BITS 64
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include "matrix.h"

enum { CONTROL = 0x00, STATUS = 0x04, ID = 0x08, CYCLES = 0x0c,
       RUNS = 0x10, CLOCK_HZ = 0x18, LATENCY = 0x1c,
       A = 0x100, B = 0x200, C = 0x400, SPAN = 0x800,
       SAMPLES = 9, MAX_RUNS = 1000000 };
#define EXPECTED_ID UINT32_C(0x4d4d0701)

static void barrier(void)
{
#if defined(__aarch64__)
    __asm__ volatile ("dmb sy" ::: "memory");
#endif
}
static uint32_t read_reg(volatile uint32_t *r, unsigned offset)
{
    uint32_t value;
    barrier(); value = r[offset / 4]; barrier();
    return value;
}
static void write_reg(volatile uint32_t *r, unsigned offset, uint32_t value)
{
    barrier(); r[offset / 4] = value; barrier();
}
static uint64_t now_ns(void)
{
    struct timespec t;
    /* Relógio Linux sem os ajustes de frequência do NTP. A leitura do
     * relógio não fica dentro do laço das multiplicações. */
    if (clock_gettime(CLOCK_MONOTONIC_RAW, &t) != 0) {
        perror("clock_gettime"); exit(EXIT_FAILURE);
    }
    return (uint64_t)t.tv_sec * UINT64_C(1000000000) + (uint64_t)t.tv_nsec;
}
static int same(const int64_t x[49], const int64_t y[49])
{
    unsigned i;
    for (i = 0; i < 49; ++i) if (x[i] != y[i]) return 0;
    return 1;
}
static int compare_u64(const void *x, const void *y)
{
    uint64_t a = *(const uint64_t *)x, b = *(const uint64_t *)y;
    return (a > b) - (a < b);
}
static int random_matrices(int16_t a[49], int16_t b[49])
{
    uint16_t raw[98];
    FILE *f = fopen("/dev/urandom", "rb");
    size_t count;
    unsigned i;
    if (!f) { perror("/dev/urandom"); return 0; }
    count = fread(raw, sizeof raw[0], 98, f);
    fclose(f);
    if (count != 98) { fprintf(stderr, "Falha lendo aleatoriedade.\n"); return 0; }
    for (i = 0; i < 49; ++i) {
        /* Distribuição uniforme em toda a faixa [-32768, 32767].
         * Nova entropia a cada execução, fora de qualquer cronometragem. */
        a[i] = (int16_t)((int32_t)raw[i] - 32768);
        b[i] = (int16_t)((int32_t)raw[49+i] - 32768);
    }
    return 1;
}

int main(int argc, char **argv)
{
    int16_t a[49], b[49];
    int64_t cpu[49], reference[49], fpga[49];
    uint64_t times[SAMPLES], clock_overhead = UINT64_MAX, base = 0;
    uint32_t runs = 10000, cycles = 0, frequency = 0, latency = 0;
    volatile uint32_t *regs = NULL;
    void *mapping = MAP_FAILED;
    size_t map_length = 0;
    unsigned i, s;
    int fd = -1, cpu_only, cpu_id, result = EXIT_FAILURE;
    char *end;

    if (argc < 2 || argc > 3) {
        fprintf(stderr, "Uso: %s ENDERECO_FISICO [repeticoes] | --cpu-only [repeticoes]\n", argv[0]);
        return EXIT_FAILURE;
    }
    cpu_only = strcmp(argv[1], "--cpu-only") == 0;
    if (!cpu_only) {
        errno = 0; base = strtoull(argv[1], &end, 0);
        if (errno || argv[1][0] == '-' || end == argv[1] || *end ||
            base % 4 || base > INT64_MAX - SPAN) {
            fprintf(stderr, "Endereço físico inválido.\n"); return EXIT_FAILURE;
        }
    }
    if (argc == 3) {
        unsigned long n;
        errno = 0; n = strtoul(argv[2], &end, 10);
        if (errno || end == argv[2] || *end || n < 1 || n > MAX_RUNS) {
            fprintf(stderr, "Repetições: de 1 a %d.\n", MAX_RUNS); return EXIT_FAILURE;
        }
        runs = (uint32_t)n;
    }
    if (!random_matrices(a, b)) return EXIT_FAILURE;
    multiply_reference(a, b, reference);
    /* O HPS tem núcleos de tipos diferentes. Mantém o processo no núcleo
     * atual, respeitando a afinidade externa (por exemplo taskset), para não
     * misturar tempos de núcleos distintos nos nove lotes. */
    cpu_id = sched_getcpu();
    if (cpu_id >= 0 && cpu_id < CPU_SETSIZE) {
        cpu_set_t mask;
        CPU_ZERO(&mask); CPU_SET(cpu_id, &mask);
        if (sched_setaffinity(0, sizeof mask, &mask) != 0) {
            perror("Não foi possível fixar afinidade CPU"); return EXIT_FAILURE;
        }
    } else { fprintf(stderr, "Não foi possível identificar o núcleo CPU.\n"); return EXIT_FAILURE; }

    if (!cpu_only) {
        long page_size = sysconf(_SC_PAGESIZE);
        uint64_t page_base;
        size_t delta;
        if (page_size <= 0) { fprintf(stderr, "Página de memória inválida.\n"); return EXIT_FAILURE; }
        page_base = base / (uint64_t)page_size * (uint64_t)page_size;
        delta = (size_t)(base - page_base); map_length = delta + SPAN;
        fd = open("/dev/mem", O_RDWR | O_SYNC);
        if (fd < 0) { perror("/dev/mem"); return EXIT_FAILURE; }
        mapping = mmap(NULL, map_length, PROT_READ | PROT_WRITE, MAP_SHARED, fd, (off_t)page_base);
        if (mapping == MAP_FAILED) { perror("mmap"); goto cleanup; }
        regs = (volatile uint32_t *)((unsigned char *)mapping + delta);
        if (read_reg(regs, ID) != EXPECTED_ID) {
            fprintf(stderr, "ID incompatível: carregue o circuito 7x7 e confira a base física.\n");
            goto cleanup;
        }
        if (read_reg(regs, STATUS) & 2) {
            fprintf(stderr, "FPGA ocupada: não execute programas concorrentes.\n"); goto cleanup;
        }
        /* Transferências não fazem parte do tempo de multiplicação. */
        write_reg(regs, CONTROL, 0);
        write_reg(regs, RUNS, runs);
        for (i = 0; i < 49; ++i) {
            write_reg(regs, A + 4*i, (uint16_t)a[i]);
            write_reg(regs, B + 4*i, (uint16_t)b[i]);
        }
    }

    /* Aquecimento fora da medição. Código em objeto separado e sem LTO:
     * cada chamada continua sendo executada mesmo com as mesmas entradas. */
    for (i = 0; i < 100; ++i) multiply_cpu(a, b, cpu);
    for (i = 0; i < 1000; ++i) {
        uint64_t t = now_ns(), overhead = now_ns() - t;
        if (overhead < clock_overhead) clock_overhead = overhead;
    }
    for (s = 0; s < SAMPLES; ++s) {
        uint64_t start = now_ns(), elapsed;
        for (i = 0; i < runs; ++i) multiply_cpu(a, b, cpu);
        elapsed = now_ns() - start;
        times[s] = elapsed > clock_overhead ? elapsed - clock_overhead : 0;
        if (!same(cpu, reference)) { fprintf(stderr, "Resultado ARM incorreto.\n"); goto cleanup; }
    }
    qsort(times, SAMPLES, sizeof times[0], compare_u64);

    if (!cpu_only) {
        uint64_t start;
        /* START e polling disparam/observam o teste. O tempo divulgado vem
         * do contador INTERNO de ciclos busy, não do cronômetro do ARM. */
        write_reg(regs, CONTROL, 1);
        start = now_ns();
        while (!(read_reg(regs, STATUS) & 1)) {
            if (now_ns() - start > UINT64_C(2000000000)) {
                fprintf(stderr, "Timeout aguardando a FPGA.\n"); goto cleanup;
            }
        }
        cycles = read_reg(regs, CYCLES);
        frequency = read_reg(regs, CLOCK_HZ);
        latency = read_reg(regs, LATENCY);
        if (frequency != 100000000 || latency != 4 || cycles != runs * latency) {
            fprintf(stderr, "Contagem/frequência inesperada no circuito 7x7.\n"); goto cleanup;
        }
        for (i = 0; i < 49; ++i) {
            uint32_t low = read_reg(regs, C + 8*i);
            uint32_t high = read_reg(regs, C + 8*i + 4);
            /* Reconstrução de 64 bits com sinal sem conversão fora de faixa.
             * A parte alta é a extensão de sinal de um resultado de 35 bits. */
            int64_t signed_high = high <= INT32_MAX ? (int64_t)high
                                  : (int64_t)high - INT64_C(4294967296);
            fpga[i] = signed_high * INT64_C(4294967296) + low;
        }
        result = same(cpu, fpga) ? EXIT_SUCCESS : EXIT_FAILURE;
        puts(result == EXIT_SUCCESS ? "Resultados ARM e FPGA coincidem." : "ERRO: resultados ARM e FPGA NÃO coincidem.");
    } else {
        result = EXIT_SUCCESS;
        puts("CPU confere com a referência; FPGA não acessada.");
    }
    printf("%s, núcleo %d: mediana %.2f ns/multiplicação; mínimo %.2f ns (9 lotes de %" PRIu32 ").\n",
           cpu_only ? "CPU local" : "ARM", cpu_id, (double)times[SAMPLES/2] / runs,
           (double)times[0] / runs, runs);
    if (!cpu_only)
        printf("FPGA: %.2f ns/multiplicação (%" PRIu32 " ciclos/op a %.0f MHz; %" PRIu32 " ciclos no lote).\n",
               1e9 * cycles / frequency / runs, latency, frequency / 1e6, cycles);
cleanup:
    if (mapping != MAP_FAILED) munmap(mapping, map_length);
    if (fd >= 0) close(fd);
    return result;
}
