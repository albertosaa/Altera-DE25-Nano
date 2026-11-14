# Base: ResourcePackage/Demonstration/SoC/gsensor/Makefile.
TARGET = MatrixMultiplication
CROSS_COMPILE ?= aarch64-none-linux-gnu-
CC = $(CROSS_COMPILE)gcc
LD = $(CROSS_COMPILE)gcc
ARCH = arm64
CFLAGS = -g -Wall -Werror -Wextra -Wpedantic -std=c11
LDFLAGS = -g -Wall -Werror
# Ligação estática permite enviar somente o executável, sem instalar bibliotecas.
# STATIC=0 recupera a ligação dinâmica usada na demonstração gsensor.
STATIC ?= 1
ifeq ($(STATIC),1)
LDFLAGS += -static
endif
HOST_CC ?= cc
BOARD ?= terasic@192.168.8.2

.PHONY: build clean check deploy
build: build/$(TARGET)

build/$(TARGET): build/main.o
	$(LD) $(LDFLAGS) $^ -o $@

build/main.o: main.c matrix.h Makefile
	mkdir -p build
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

build/native/$(TARGET): main.c matrix.h
	mkdir -p build/native
	$(HOST_CC) $(CFLAGS) main.c -o $@

check: build/native/$(TARGET)
	./build/native/$(TARGET) --cpu-only

# Somente o ELF é copiado. Nenhuma compilação é realizada na placa.
deploy: build/$(TARGET)
	scp $< $(BOARD):MatrixMultiplication

clean:
	$(RM) -r build
