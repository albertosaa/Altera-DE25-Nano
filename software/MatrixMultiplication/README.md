# MatrixMultiplication — ARM versus FPGA

Primeiro projeto didático: multiplicar duas matrizes 2×2 no ARM e na FPGA e
comparar os quatro resultados. Código e comentários em português.

**Validado na placa física em 14/11/2026.** O procedimento completo está no
[guia de compilação, programação e execução](../../docs/GUIA_MATRIX_MULTIPLICATION.md).

```text
A = [1 2]    B = [5 6]    C = A × B = [19 22]
    [3 4]        [7 8]                [43 50]

Programa C no ARM → ponte lightweight HPS/FPGA → registradores Avalon-MM
                                               ↓
                                     multiplicadores/DSPs na FPGA
                                               ↓
Programa C no ARM ← leitura e comparação ← quatro resultados
```

O FPGA contém um circuito, não um programa C: os operadores `*` do Verilog são
sintetizados como hardware. Os oito produtos podem ser calculados em paralelo.
O Quartus sintetizou o núcleo com **4 elementos DSP** neste laptop.

## Arquivos

- `main.c`: acesso aos registradores, cálculo no ARM e comparação.
- `matrix.h`: multiplicação em C padrão, independente do Linux.
- `Makefile`: cross-compiling, teste nativo e envio do executável.
- [Parte FPGA](../../fpga/MatrixMultiplication/README.md): Verilog, simulação,
  projeto Quartus e integração com o GHRD.

As entradas são inteiros com sinal de 16 bits. Uma soma de dois produtos exige
33 bits no pior caso; o C usa `int64_t` e o hardware devolve o resultado com
extensão de sinal para 64 bits. Assim, inclusive `-32768` é suportado.

## Compilar no laptop

O padrão segue `ResourcePackage/Demonstration/SoC/gsensor/Makefile`:

- `ARCH = arm64`;
- `CROSS_COMPILE = aarch64-none-linux-gnu-`;
- compilador e linker: `$(CROSS_COMPILE)gcc`;
- opções originais `-g -Wall -Werror`.

Adicionamos C11 e avisos extras. A ligação é estática por padrão para enviar
somente o executável, sem instalar bibliotecas na placa. `STATIC=0` permite
ligação dinâmica, cuja libc/loader precisam ser compatíveis com a imagem Linux.

A demonstração `SoC_FPGA/GHRD/software/hps_debug/build.sh` referencia a toolchain
Arm GNU `11.2-2022.02`, com o mesmo prefixo. Não use `aarch64-none-elf-` (bare metal)
nem um compilador Nios V: o destino aqui é Linux AArch64 no HPS.

Na raiz do repositório, com a toolchain das demonstrações no PATH:

```bash
make -C software/MatrixMultiplication
file software/MatrixMultiplication/build/MatrixMultiplication
```

O ELF deve ser `ARM aarch64`, não x86-64. Também é possível informar um prefixo
com caminho absoluto por `CROSS_COMPILE=/caminho/bin/aarch64-none-linux-gnu-`.

### Compilador disponível neste laptop

O prefixo das demonstrações não foi encontrado nas localizações examinadas.
A compilação foi validada com GCC 12.2.0 AArch64 Linux instalado pelo Vitis:

```bash
make -C software/MatrixMultiplication \
  CROSS_COMPILE=/opt/Xilinx/Vitis/2024.1/gnu/aarch64/lin/aarch64-linux/bin/aarch64-linux-gnu-
```

O executável gerado é ELF de 64 bits AArch64, estaticamente ligado. Esse caminho
é específico deste laptop; não é requisito para outro computador. Ao trocar
compilador ou opções, execute `make -C software/MatrixMultiplication clean` antes
de recompilar, para não reutilizar objetos anteriores.

## Teste somente do C, no laptop

```bash
make -C software/MatrixMultiplication check
```

Esse alvo usa o compilador nativo e verifica os valores `19, 22, 43, 50`.
Não acessa nem simula a FPGA. A simulação do hardware é descrita no guia FPGA.

## Preparar o hardware antes de executar a comparação

O bitstream original da placa **não contém** este novo multiplicador.
Primeiro integre o componente ao GHRD, gere o sistema e compile/programe a FPGA
conforme o [guia da parte FPGA](../../fpga/MatrixMultiplication/README.md).
A ponte lightweight precisa estar habilitada pelo fluxo de boot/configuração.

O programa exige a base física como argumento: ela deve corresponder ao
Address Map do sistema realmente carregado e ao mapa HPS da imagem em uso.
Não execute acessos MMIO com uma base presumida ou uma ponte desabilitada:
uma transação pode não responder, e o timeout do programa não interrompe um
acesso ao barramento que já esteja bloqueado.

## Enviar somente o executável

Na raiz do repositório, depois de compilar:

```bash
scp software/MatrixMultiplication/build/MatrixMultiplication terasic@192.168.8.2:MatrixMultiplication
ssh terasic@192.168.8.2
```

`192.168.8.2` é a conexão Ethernet direta já validada. Pela rede USB, use
`192.168.7.2`. O alvo `make deploy BOARD=terasic@192.168.8.2` também copia somente
o executável; informe o mesmo `CROSS_COMPILE` utilizado na compilação.

Na placa, pode-se testar primeiro sem acessar a FPGA:

```bash
./MatrixMultiplication --cpu-only
```

Para comparar, após conferir o endereço físico do componente:

```bash
sudo ./MatrixMultiplication 0x20010100
```

Neste projeto, `0x20010100` é a soma da base física da ponte lightweight
`0x20000000` com o deslocamento `0x00010100` escolhido no script de integração.
O programa verifica o ID `0x4d4d0001` antes de escrever.
O ID não substitui a conferência prévia do mapa e da ponte.

Saída esperada ao final:

```text
Resultado no ARM:
[ 19  22 ]
[ 43  50 ]
Resultado na FPGA:
[ 19  22 ]
[ 43  50 ]
SUCESSO: ARM e FPGA concordam.
```

Retorno zero indica igualdade; falhas de acesso, ID, timeout ou comparação
retornam um código diferente de zero. Execute apenas uma instância por vez:
os registradores não implementam arbitragem entre programas concorrentes.

## O que foi validado

- Teste nativo do C no laptop.
- Cross-compiling AArch64 Linux e formato do executável estático.
- Simulação RTL: 104 pares de matrizes, incluindo negativos e limites.
- Síntese do núcleo no Quartus Pro 26.3: 4 elementos DSP.
- Integração em cópia limpa do GHRD e geração do HDL do subsistema alterado.

- Compilação completa do GHRD modificado e programação com `golden_top_hps.sof`.
- Execução no ARM e comparação na FPGA física em `0x20010100`: os quatro
  resultados foram iguais (`19, 22, 43, 50`).

Enviar o ELF não carrega o circuito na FPGA; o circuito é configurado
separadamente pelo Quartus/fluxo de configuração da placa. Os testes físicos
realizados usaram as matrizes fixas deste exemplo; os limites foram simulados.
