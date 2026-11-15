# MatrixMultiplication7x7 — comparação do tempo de cálculo

Versão separada do exemplo 2×2, que permanece preservado. A e B são matrizes
7×7 de inteiros com sinal de 16 bits. A cada execução, o programa lê nova
aleatoriedade de `/dev/urandom`, cobrindo uniformemente `[-32768, 32767]`.
Os resultados usam `int64_t`; o circuito usa 35 bits para a soma de sete produtos.

**Teste físico concluído em 15/11/2026:** os 49 resultados coincidiram. No núcleo
lógico 0, a mediana ARM foi 1.378,20 ns/op e o mínimo 1.376,61 ns/op; a FPGA
contou 40 ns/op a 100 MHz. Veja o [relatório completo do experimento](../../docs/RELATORIO_MATRIX_MULTIPLICATION_7x7.md),
incluindo a escolha de 7×7, os limites de DSP e as condições da comparação.

O programa não imprime as matrizes. Em funcionamento normal, imprime somente:

- Se os 49 resultados ARM e FPGA coincidem.
- Tempo ARM por multiplicação: mediana e mínimo de nove lotes.
- Tempo de cálculo FPGA por multiplicação, calculado de seu contador de ciclos.

## Compilar no laptop

Na raiz do repositório, com a toolchain das demonstrações no PATH:

```bash
make -C software/MatrixMultiplication7x7
```

Neste laptop, o compilador disponível é AArch64 Linux GCC 12.2.0 do Vitis:

```bash
make -C software/MatrixMultiplication7x7 \
  CROSS_COMPILE=/opt/Xilinx/Vitis/2024.1/gnu/aarch64/lin/aarch64-linux/bin/aarch64-linux-gnu-
```

O Makefile mantém `ARCH=arm64`, prefixo padrão `aarch64-none-linux-gnu-`, GCC
como compilador/linker e `-g -Wall -Werror`, como a demonstração `SoC/gsensor`.
Adiciona `-O3` para medir C otimizado, C11 e `-fno-lto`. A ligação é estática:
somente o executável é enviado à placa. Não há dependência de BLAS ou drivers
novos na placa. A multiplicação é C padrão; MMIO, aleatoriedade, afinidade e
relógio usam interfaces Linux.

Se trocar toolchain ou opções, use `make -C software/MatrixMultiplication7x7 clean`
antes de recompilar.

## Testar o C e a simulação

```bash
make -C software/MatrixMultiplication7x7 check
make -C fpga/MatrixMultiplication7x7 sim
```

Há 104 pares de teste no C e 104 no RTL, incluindo zeros, identidade, valores
negativos e extremos. Os extremos excedem 32 bits, verificando também o formato
de leitura dos resultados. O RTL verifica quatro ciclos/op, lotes, reset e
proteção contra escritas durante busy.

O teste nativo informa tempos da **CPU do laptop**, não do ARM da placa.

## Preparar e carregar o circuito 7×7

Consulte a [parte FPGA](../../fpga/MatrixMultiplication7x7/README.md).
É necessário carregar o novo `golden_top_hps.sof` da pasta **7x7**, não o `.sof`
2×2. Esta versão tem nova base física e novo ID para distinguir os protocolos:

| Parâmetro | Valor |
| --- | --- |
| Base física no HPS | `0x20011000` |
| Offset no subsistema | `0x00011000` |
| ID esperado | `0x4d4d0701` |
| Clock configurado no GHRD | 100 MHz |
| Latência | 4 ciclos por multiplicação completa |

A janela do componente agora tem 2048 bytes. Os valores de endereço são para
o sistema descrito neste repositório; verifique o mapa se modificar o GHRD.

## Copiar e executar

No laptop, a partir da raiz do repositório:

```bash
scp software/MatrixMultiplication7x7/build/MatrixMultiplication7x7 \
  terasic@192.168.8.2:MatrixMultiplication7x7
ssh terasic@192.168.8.2
```

Na placa, após carregar o novo circuito:

```bash
sudo ./MatrixMultiplication7x7 0x20011000
```

São usadas 10.000 repetições por lote por padrão. Opcionalmente:

```bash
sudo ./MatrixMultiplication7x7 0x20011000 100000
```

O limite é 1.000.000. As mesmas A e B aleatórias são reutilizadas nos lotes
de uma execução para amortizar a medição; a próxima execução sorteia novas A e B.

Para medir apenas no ARM, sem tocar na FPGA, inclusive com o circuito antigo:

```bash
./MatrixMultiplication7x7 --cpu-only
```

O programa fixa sua afinidade no núcleo em que começou e informa esse número
na linha do tempo. Isso evita misturar núcleos diferentes do HPS nos nove lotes.
Para escolher um núcleo, use, por exemplo, `taskset -c 0` antes do comando,
desde que esse núcleo esteja disponível. Não se deve atribuir o mesmo desempenho
a todos os núcleos: o HPS possui Cortex-A55 e Cortex-A76.

## Como os tempos são obtidos

### ARM

1. Gera A/B, calcula uma referência e prepara o MMIO fora da medição.
2. Aquece o cálculo com 100 chamadas.
3. Estima o custo mínimo das leituras de relógio com 1.000 pares consecutivos.
4. Mede nove lotes com `CLOCK_MONOTONIC_RAW`; cada lote executa N multiplicações.
5. Subtrai uma estimativa do custo de cronometragem por lote e divide por N.
6. Ordena os nove valores e mostra mediana e mínimo. Verifica o resultado de
   cada lote fora da região cronometrada.

`multiply_cpu` está em `matrix.c`, compilado em objeto separado e sem LTO.
Assim o chamador não pode eliminar as operações repetidas nem mover o cálculo
para fora do laço. A função pode ser otimizada/vetorizada internamente por GCC.

O número inclui o pequeno custo do laço e da chamada da função, mas exclui
aleatoriedade, verificação, impressão, abertura/mapeamento de memória e comunicação.
São tempos de cálculo com dados aquecidos em cache. Afinidade não elimina
interrupções, escalonamento ou mudanças de frequência/temperatura; a mediana
representa a execução típica e o mínimo é uma aproximação do melhor caso observado.
Não é uma comparação com a melhor implementação ARM possível em assembly/BLAS.

### FPGA

Após carregar A e B uma vez, o ARM escreve RUNS e START. O próprio circuito
executa N multiplicações completas e conta os ciclos de cálculo. O ARM espera
DONE e lê o contador e os resultados; nenhum desses acessos entra no tempo
informado como cálculo FPGA.

```text
tempo por multiplicação = ciclos do lote / N / frequência do clock
                         = 4 / 100.000.000
                         = 40 ns, se o circuito atender a 100 MHz
```

A frequência vem de um registrador que declara o clock configurado, **não de
um frequencímetro**. A estimativa é sustentada pela análise de temporização
pós-roteamento, que passou setup/hold a 100 MHz. A implementação completa usa
147 DSPs e 41% dos ALMs. A execução física 7×7 confirmou 40.000 ciclos para
10.000 operações e igualdade dos 49 resultados. Os 40 ns não são uma medição
externa com osciloscópio. Consulte no guia FPGA os avisos de sign-off herdados
do GHRD.

As quatro etapas são produtos, soma de pares, soma de grupos de quatro e soma
final. São operações não sobrepostas: um novo cálculo começa após o anterior.
O número é latência de cálculo desta implementação, não vazão de um pipeline
que recebe novas matrizes a cada ciclo e não tempo total de uma requisição ARM.
Para uma chamada real isolada, escrever 98 entradas e ler 49 resultados pode
custar muito mais que os 40 ns; esse custo foi excluído a pedido do experimento.

## Interpretação dos resultados

A comparação em nanosegundos usa a mesma operação matemática, mas representa
um algoritmo sequencial/vetorizável em C versus hardware espacial com 343 produtos
simultâneos. Não mede transferências, não mede programação do bitstream e não
implica que uma aplicação completa será acelerada na mesma proporção.

O código de saída é zero quando a verificação passa. Com `--cpu-only`, a mensagem
deixa explícito que apenas a referência CPU foi verificada.

## Referências

- [Quartus e mapa de registradores](../../fpga/MatrixMultiplication7x7/README.md).
- [Procedimento físico validado no exemplo 2×2](../../docs/GUIA_MATRIX_MULTIPLICATION.md).
- [GCC — otimização e LTO](https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html).
