# Convenções da demonstração gsensor: ARCH, prefixo, GCC como CC/LD e avisos.
TARGET = MatrixMultiplication7x7
CROSS_COMPILE ?= aarch64-none-linux-gnu-
CC = $(CROSS_COMPILE)gcc
LD = $(CROSS_COMPILE)gcc
ARCH = arm64
# -O3 é necessário para comparar com C otimizado. Sem LTO para preservar
# as chamadas de multiply_cpu em objeto separado durante o benchmark.
CFLAGS = -O3 -g -Wall -Werror -Wextra -Wpedantic -std=c11 -fno-lto
LDFLAGS = -g -Wall -Werror -fno-lto
STATIC ?= 1
ifeq ($(STATIC),1)
LDFLAGS += -static
endif
HOST_CC ?= cc
BOARD ?= terasic@192.168.8.2

.PHONY: build check deploy clean
build: build/$(TARGET)
build/$(TARGET): build/main.o build/matrix.o
	$(LD) $(LDFLAGS) $^ -o $@
build/%.o: %.c matrix.h Makefile
	mkdir -p build
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@
build/native/main.o: main.c matrix.h Makefile
	mkdir -p build/native
	$(HOST_CC) $(CFLAGS) -c $< -o $@
build/native/matrix.o: matrix.c matrix.h Makefile
	mkdir -p build/native
	$(HOST_CC) $(CFLAGS) -c $< -o $@
build/native/$(TARGET): build/native/main.o build/native/matrix.o
	$(HOST_CC) -fno-lto $^ -o $@
build/native/test_matrix: tests/test_matrix.c matrix.c matrix.h Makefile
	mkdir -p build/native
	$(HOST_CC) $(CFLAGS) -I. tests/test_matrix.c matrix.c -o $@
check: build/native/$(TARGET) build/native/test_matrix
	./build/native/test_matrix
	./build/native/$(TARGET) --cpu-only 1000
deploy: build/$(TARGET)
	scp $< $(BOARD):$(TARGET)
clean:
	$(RM) -r build
