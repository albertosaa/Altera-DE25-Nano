# MatrixMultiplication7x7 — circuito e medição

Este projeto preserva o exemplo 2×2 e cria um novo periférico para multiplicar
matrizes 7×7, com entradas signed de 16 bits e resultados de 35 bits. O programa
[C correspondente](../../software/MatrixMultiplication7x7/README.md) sorteia A/B,
compara os resultados e imprime somente a confirmação e os tempos.

O [relatório completo do experimento](../../docs/RELATORIO_MATRIX_MULTIPLICATION_7x7.md)
registra a discussão inicial, as tentativas de empacotamento e o teste físico
final: resultados coincidentes, ARM mediano de 1.378,20 ns/op no núcleo lógico 0
e FPGA com 40 ns/op pelo contador de ciclos.

## Arquitetura

Todos os **343 produtos** existem simultaneamente no circuito. A árvore de
somas tem três níveis registrados; são quatro ciclos para uma matriz completa:

| Ciclo após START | Operação |
| --- | --- |
| 1 | Registra 343 produtos de 32 bits |
| 2 | Soma pares, com extensão de sinal para 33 bits |
| 3 | Soma grupos, com extensão para 34 bits |
| 4 | Registra 49 resultados de 35 bits |

Para um lote, o circuito repete essa sequência N vezes, mantendo as entradas
estáveis, e incrementa CYCLES apenas durante os ciclos de cálculo. DONE só
fica ativo no final do lote. Escrever durante busy é ignorado. A frequência
declarada é 100 MHz, a mesma do clock de periféricos do GHRD.

## Empacotamento e recursos

A tentativa de implementar tudo em DSPs mostrou o limite da estimativa ideal:
o agrupamento por saída exigiu 196 DSPs. Uma segunda tentativa, preservando
produtos independentes, estimou 172 após merging, mas o Fitter precisou de 215
blocos devido às restrições físicas de empacotamento. A placa dispõe de 188.

A implementação usada agora coloca **294 produtos em DSPs e 49 produtos em
ALMs**: os seis primeiros termos de cada saída usam três pares de multiplicadores
DSP, e o sétimo usa lógica programável. Os **343 produtos continuam simultâneos**;
nenhum multiplicador é reutilizado durante os sete termos da matriz.

A síntese dessa versão estima **147 DSPs** e 9.936 ALMs para o núcleo isolado.
O Fitter confirmou **147/188 DSPs** no sistema completo, com **18.986/46.800
ALMs (41%)** incluindo o GHRD.
Esse caso mostra por que a contagem ideal de multiplicadores não é uma garantia
de implementação física. A simulação cobre a mesma aritmética com ambos os tipos
de multiplicadores; `multstyle` muda o mapeamento, não o resultado matemático.

## Simular e abrir no Quartus

```bash
make -C fpga/MatrixMultiplication7x7 sim
```

O testbench usa 104 pares de matrizes e uma referência de 64 bits, verifica
negativos/extremos, contagem de ciclos, lotes, busy e reset durante execução.

Para estudar somente o núcleo, abra:

```text
fpga/MatrixMultiplication7x7/quartus/MatrixMultiplication7x7.qpf
```

O projeto isolado serve para RTL Viewer/síntese; a programação da placa deve
usar o GHRD completo descrito abaixo.

## Preparar e compilar o GHRD

Na raiz do repositório, com Quartus e Platform Designer no PATH:

```bash
export PATH=/home/asaa/altera_pro/26.3/quartus/bin:/home/asaa/altera_pro/26.3/quartus/sopc_builder/bin:$PATH
```

O script aceita como origem a cópia 2×2 já atualizada para Quartus 26.3:

```bash
sh fpga/MatrixMultiplication7x7/scripts/prepare_ghrd.sh \
  /home/asaa/Desktop/Cognus/DE25-Nano/codex/fpga/MatrixMultiplication/build/ghrd_final
```

Sem argumento, usa o GHRD original do ResourcePackage e poderá exigir os
upgrades de IP já documentados no guia 2×2. Não modifica o projeto de origem.
Cria `build/ghrd_7x7`, remove `matrix_0` do novo sistema caso exista e adiciona
`matrix7_0`. Recusa sobrescrever uma cópia existente. Um segundo argumento
permite escolher um diretório de saída absoluto diferente.

O script separa bitstreams antigos copiados da origem em
`output_files/reference_bitstreams/`, para não confundi-los com os do 7×7.

Para atualizar o RTL e compilar a cópia preparada:

```bash
sh fpga/MatrixMultiplication7x7/scripts/build_ghrd.sh
```

Esse script atualiza o componente, gera o subsistema e `qsys_top`, compila
`golden_top` e incorpora o SPL com `quartus_pfg`, seguindo o fluxo já validado.
Não programa a placa. As ferramentas Platform Designer precisam poder se
comunicar entre processos locais; um sandbox sem sockets pode impedir a geração.

O arquivo para abrir no Quartus é:

```text
fpga/MatrixMultiplication7x7/build/ghrd_7x7/golden_top.qpf
```

Depois da compilação bem-sucedida, use no Programmer o novo:

```text
fpga/MatrixMultiplication7x7/build/ghrd_7x7/output_files/golden_top_hps.sof
```

Não selecione o `.sof` 2×2, nem um arquivo em `reference_bitstreams/`.
As instruções de Hardware Setup, udev e bootloader estão no
[guia de programação física](../../docs/GUIA_MATRIX_MULTIPLICATION.md).

## Mapa de registradores

Os offsets abaixo são em **bytes**. A janela tem 2048 bytes e o endereço
Avalon-MM tem nove bits de **palavras**. A base relativa ao lightweight é
`0x00011000`, dentro da janela de 17 bits do `pb_cpu_0.m0`, sem sobrepor os
periféricos originais. No HPS deste GHRD, a base física é **`0x20011000`**.

| Offset | Registrador | Descrição |
| --- | --- | --- |
| `0x00` | CONTROL | Escrever 1 inicia; 0 limpa DONE quando idle |
| `0x04` | STATUS | bit 0 DONE; bit 1 busy |
| `0x08` | ID | `0x4d4d0701` |
| `0x0c` | CYCLES | Ciclos de cálculo do lote; valor esperado `4 × RUNS` |
| `0x10` | RUNS | 1 a 1.000.000 operações não sobrepostas; padrão 1 |
| `0x18` | CLOCK_HZ | Clock configurado: 100.000.000 Hz |
| `0x1c` | LATENCY | 4 ciclos por multiplicação |
| `0x100` a `0x1c0` | A | 49 palavras; 16 bits inferiores signed |
| `0x200` a `0x2c0` | B | 49 palavras; 16 bits inferiores signed |
| `0x400` a `0x584` | C | 49 pares de palavras baixa/alta; signed estendido a 64 bits |

Todos os elementos estão em ordem de linhas. Resultados ficam estáveis até
o próximo ciclo final de cálculo ou reset. Execute somente um cliente por vez.

## Estimativa de tempo

Latência funcional simulada: **4 ciclos**. Com clock de 100 MHz, a estimativa
é **40 ns por multiplicação completa**, excluindo entrada/saída por MMIO.

### Validação pós-roteamento em 15/11/2026

O build completo terminou com sucesso às 13:05:28 e o Programming File Generator
gerou o `golden_top_hps.sof` às 13:05:30, no Quartus Pro 26.3.0 Build 114.

| Verificação | Resultado |
| --- | --- |
| DSPs físicos no sistema completo | 147 / 188 (78%) |
| ALMs no sistema completo | 18.986 / 46.800 (41%) |
| Clock de cálculo configurado | 100 MHz, período 10 ns |
| Setup do domínio de cálculo | Pass; slack +2,782 ns |
| Hold do domínio de cálculo | Pass; slack mínimo 0,000 ns |
| Timing Closure | Pass |
| Fmax reportada para esse domínio | 138,54 MHz; operação mantida em 100 MHz |
| Latência estimada sustentada pelos caminhos analisados | 40 ns |

Esses dados estão nos relatórios locais `output_files/golden_top.flow.rpt`,
`golden_top.fit.rpt` e `golden_top.sta.rpt`, dentro de `build/ghrd_7x7`.
A Fmax não é a frequência realmente usada e não autoriza aumentar o clock sem
reconfigurar e verificar todo o sistema.

O painel global `Design Closure Summary` ainda marca Fail por avisos também
presentes na cópia 2×2: `RES-50001` (reset assíncrono) e `TMC-20012` (restrição
de saída ausente). As quatro saídas sem restrição são `LED[0]`, `LED[1]`,
`LED[2]` e `LED[7]`; não há clocks nem entradas sem restrição. Por isso, o
resultado acima é uma validação de temporização dos caminhos analisados,
não uma declaração de ausência de todos os avisos de sign-off do GHRD.

O usuário carregou o novo bitstream e executou o programa na placa. O contador
retornou 40.000 ciclos para 10.000 operações, equivalentes a 40 ns/op pelo clock
nominal de 100 MHz. Os 49 resultados finais coincidiram com o ARM.

No ARM, o executável mediu mediana de 1.378,20 ns/op e mínimo de 1.376,61 ns/op
no núcleo lógico 0, em nove lotes de 10.000 operações. Tempos do laptop x86 não
foram usados para estimar esses números. A razão mediana ARM/FPGA foi 34,455×,
excluindo comunicação; a saída original e as limitações estão no relatório.

O contador mede ciclos, não a frequência física do oscilador. O clock declarado
no registrador deve coincidir com o clock realmente conectado ao componente.
