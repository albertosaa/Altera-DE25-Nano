# Experimento 7×7: multiplicação inteira no ARM e na FPGA DE25-Nano

**Data:** 15/11/2026. **Projeto:** `MatrixMultiplication7x7`.
**Estado:** código compilado no laptop, circuito implementado no Quartus e
comparação executada com sucesso na placa física pelo usuário.

## 1. Resultado principal

Para uma multiplicação de duas matrizes 7×7 de inteiros com sinal de 16 bits,
os **49 resultados do ARM e da FPGA coincidiram**. Na execução registrada:

| Medida | Tempo por multiplicação completa |
| --- | ---: |
| ARM, núcleo lógico 0 — mediana de nove lotes | 1.378,20 ns = 1,37820 µs |
| ARM, núcleo lógico 0 — mínimo dos nove lotes | 1.376,61 ns |
| FPGA — contador interno, convertido pelo clock nominal | 40,00 ns |
| Razão entre a mediana ARM e o tempo FPGA | **34,455× ≈ 34,46×** |

O experimento mede o **cálculo**, excluindo geração aleatória, impressão e
transferências ARM–FPGA. O fator acima não é um ganho de desempenho de ponta
a ponta de uma aplicação que precisa enviar e receber cada matriz.

## 2. Discussão inicial: por que escolher 7×7?

O ponto de partida foi o exemplo [MatrixMultiplication 2×2](GUIA_MATRIX_MULTIPLICATION.md),
já validado na placa. Ele usou oito produtos e quatro blocos DSP. A pergunta
seguinte foi qual dimensão quadrada permitiria calcular todos os produtos
simultaneamente, sem reutilizar um multiplicador para termos distintos.

O relatório do Quartus identificou **188 blocos DSP** disponíveis no dispositivo.
A capacidade anunciada corresponde a **376 multiplicadores de 18×19 bits**.
Os operandos de 16 bits deste experimento cabem nessa largura. Cada bloco DSP
tem recursos para dois produtos nesse modo, desde que o empacotamento seja
compatível com o restante do circuito.

Para o algoritmo convencional:

```text
C[i,j] = soma, para k = 0 ... N−1, de A[i,k] × B[k,j]

Número de saídas:                   N²
Produtos por saída:                N
Multiplicações escalares totais:    N³
Mínimo ideal de DSPs:               teto(N³ / 2)
```

A tabela que motivou a escolha foi:

| Matrizes | Produtos simultâneos, N³ | DSPs mínimos, supondo dois produtos por bloco | Interpretação inicial |
| --- | ---: | ---: | --- |
| 2×2 | 8 | 4 | Confirmado no projeto inicial |
| 4×4 | 64 | 32 | Folga considerável de DSPs |
| 6×6 | 216 | 108 | Dentro do orçamento ideal |
| **7×7** | **343** | **172** | Próximo do limite, ainda abaixo de 188 na estimativa |
| 8×8 | 512 | 256 | Acima do orçamento se todos os produtos usarem somente DSPs |

**Empacotamento ideal de dois produtos** significa utilizar os dois
multiplicadores de cada bloco físico. Não significa comprimir os valores nem
reduzir a precisão dos operandos. A divisão por dois é um limite inferior de
recursos, não uma garantia de que o Fitter consiga realizar essa combinação.

O usuário escolheu avançar diretamente para 7×7. A hipótese a verificar era
que o paralelismo caberia no dispositivo, e não que os 172 DSPs já estivessem
comprovados. Somadores, registradores, conexões, sinais de controle, frequência
e restrições de empacotamento também influenciam a implementação física.

Essa tabela não estabelece um máximo absoluto para a placa: multiplicadores
também podem ser construídos em ALMs, como ocorreu neste experimento. Além
disso, reutilização temporal, blocagem e matrizes maiores mudam completamente
o orçamento de hardware. Não foram explorados esses limites gerais.

## 3. Objetivo, escopo e ambiente

O objetivo foi comparar uma implementação C otimizada no ARM com um circuito
espacial na FPGA para a mesma operação matemática, imprimindo somente a
confirmação dos resultados e os tempos. O exemplo 2×2 foi preservado.

| Item | Configuração utilizada |
| --- | --- |
| Placa | Terasic DE25-Nano, Agilex 5 SoC |
| Dispositivo selecionado no projeto GHRD | `A5EB013BB23BE4SCS` |
| HPS | Núcleos Cortex-A55 e Cortex-A76; este teste registrou somente o índice lógico 0 |
| Kernel informado na preparação da placa | `6.12.11-gd7d192a9ddd9` |
| Quartus | Prime Pro 26.3.0 Build 114 |
| GHRD de referência | Demonstração Terasic originalmente 25.1, atualizada no projeto 2×2 |
| Cross-compiler usado | GCC 12.2.0 AArch64 Linux instalado pelo Vitis |
| Compilação | No laptop Linux; somente o executável C é enviado à placa |
| Carga do circuito | USB-Blaster, arquivo `.sof` com SPL do HPS |
| Acesso ao Linux da placa | SSH por Ethernet direta; placa `192.168.8.2` |

O tipo específico do núcleo lógico 0, sua frequência efetiva, governador de
frequência, temperatura e carga de outros processos não foram registrados.
Não se atribui o resultado automaticamente ao Cortex-A55 ou ao Cortex-A76.

## 4. Organização e criação do código

Foram criados dois diretórios separados, com comentários em português:

```text
software/MatrixMultiplication7x7/
  main.c                  Interface Linux, aleatoriedade, benchmark e comparação
  matrix.h                Dimensões e interface do cálculo
  matrix.c                Cálculo otimizado e referência independente
  Makefile                Cross-compiling, teste nativo e SCP
  tests/test_matrix.c     Testes numéricos no laptop

fpga/MatrixMultiplication7x7/
  rtl/matrix7_mm.v         Periférico Avalon-MM e circuito aritmético
  ip/matrix7_mm_hw.tcl     Componente para o catálogo do Platform Designer
  sim/tb_matrix7_mm.sv     Testbench funcional e de contagem de ciclos
  quartus/                Projeto isolado para síntese e visualização
  scripts/                Preparação da cópia GHRD e compilação completa
```

O cálculo numérico usa C padrão. Acesso a `/dev/mem`, `mmap`, afinidade de CPU,
relógio e `/dev/urandom` usam interfaces Linux; as barreiras MMIO AArch64 usam
uma extensão do compilador. A aplicação não depende de BLAS nem de um driver
novo para o multiplicador.

## 5. Dados aleatórios e precisão

A cada execução, o programa obtém 98 valores de 16 bits de `/dev/urandom` e
os transforma em entradas uniformes em **[−32.768, 32.767]**, divididas entre
A e B. As matrizes são armazenadas em ordem de linhas.

Dentro de uma execução, os lotes usam o mesmo par A/B. Uma nova execução
sorteia outro par. Isso atende ao requisito de aleatoriedade por execução e
permite amortizar a medição sem cronometrar a geração dos dados.

| Etapa | Largura |
| --- | --- |
| Entradas A e B | 16 bits com sinal |
| Produto individual | 32 bits com sinal |
| Soma de pares | 33 bits com sinal |
| Soma de grupos de quatro | 34 bits com sinal |
| Resultado RTL | 35 bits com sinal, escolha conservadora |
| Resultado no C e formato de leitura | `int64_t`, 64 bits com sinal |

A extensão de sinal é feita antes das somas. O resultado é lido por duas
palavras de 32 bits. Esse cuidado é necessário porque sete produtos podem
exceder 32 bits: sete vezes `−32768 × −32768` resulta em **7.516.192.768**.

As matrizes aleatórias da execução física não foram impressas nem salvas.
Portanto, é possível reproduzir o método e a distribuição dos dados, mas não
reconstituir aquele par exato A/B a partir da saída registrada.

## 6. Evolução da implementação e limite de DSPs

As tentativas de síntese e implementação mostraram a diferença entre uma
contagem ideal de multiplicadores e o consumo físico efetivo:

| Tentativa | Estratégia | Resultado | Decisão |
| --- | --- | --- | --- |
| 1 | Todos os produtos em DSPs; agrupamento das somas por saída | Síntese: 196 DSPs | Excede os 188 disponíveis |
| 2 | Produtos independentes, com `preserve`/`keep` para tentar empacotamento global | Síntese estimou 172 após merging; Fitter exigiu 215 | Implementação física rejeitada por excesso de DSPs |
| **Final** | Seis termos por saída em DSPs; sétimo termo em ALMs | **Fitter: 147 DSPs** | Compilou e foi executada na placa |

Na primeira tentativa, sete termos por saída acabaram exigindo quatro blocos:

```text
49 saídas × teto(7 / 2) = 49 × 4 = 196 DSPs
```

Na segunda, a estimativa `teto(343/2) = 172` não se confirmou no posicionamento.
O Fitter registrou `Design uses 215 DSP blocks, but only 188 DSP blocks are
available in the device`. As incompatibilidades individuais de empacotamento
não foram investigadas uma a uma; a evidência permite afirmar que o mapeamento
tentado excedeu o orçamento físico, sem atribuir uma causa específica não medida.

A solução final manteve a dimensão e o paralelismo:

```text
Em DSPs:   49 saídas × 6 produtos = 294 produtos → 147 blocos DSP
Em ALMs:   49 saídas × 1 produto  =  49 produtos
Total:                                  343 produtos simultâneos
```

O RTL usa `multstyle="dsp"` nos seis primeiros termos e `multstyle="logic"`
no sétimo. A árvore de somas completa o resultado. **Não houve reutilização
de um multiplicador para calcular sucessivamente os sete termos.** A FPGA
combina DSPs e lógica programável para executar todos os produtos em paralelo.

## 7. Arquitetura e latência do circuito

O circuito tem quatro etapas registradas, contadas a partir do START aceito:

| Ciclo | Operação conceitual no RTL |
| --- | --- |
| 1 | Registra os 343 produtos de A e B |
| 2 | Soma pares de produtos |
| 3 | Soma grupos de quatro termos |
| 4 | Registra as 49 somas finais e completa a operação |

O circuito repete essa sequência pelo número configurado em RUNS. Os
operandos permanecem estáveis durante o lote, e escritas são ignoradas enquanto
busy está ativo. DONE é ativado no fim do lote; CYCLES conta os ciclos busy.

As repetições **não são sobrepostas**. O circuito não recebe uma nova matriz
a cada ciclo. Os quatro ciclos representam a latência/intervalo de operação
desta implementação, não a vazão máxima de uma arquitetura com fluxo contínuo.

## 8. Comunicação ARM–FPGA

O programa mapeia `/dev/mem` com `mmap`. Os acessos de 32 bits usam `volatile`
e barreiras `dmb sy` em AArch64 para ordenar MMIO. O protocolo é:

1. Verificar o ID e se o periférico está livre.
2. Limpar DONE, configurar RUNS e enviar os 98 elementos de A/B.
3. Executar a medição CPU, com A/B já carregadas na FPGA.
4. Escrever START, aguardar DONE e ler o contador.
5. Ler os 49 resultados e comparar com o ARM.

| Parâmetro | Valor |
| --- | --- |
| Instância no Platform Designer | `matrix7_0` |
| Offset no subsistema lightweight | `0x00011000` |
| Base física no HPS | **`0x20011000`** |
| Janela de registradores | 2048 bytes |
| ID | `0x4d4d0701` |
| Clock declarado pelo periférico | 100.000.000 Hz |

O mapa completo está no [README FPGA](../fpga/MatrixMultiplication7x7/README.md).
A base e o ID são diferentes dos do exemplo 2×2. O circuito precisa estar
carregado e a ponte operacional antes de acessar seu endereço físico.

## 9. Cross-compiling e prevenção de otimizações indevidas

O Makefile segue as definições da demonstração
`ResourcePackage/Demonstration/SoC/gsensor/Makefile`: `ARCH=arm64`, prefixo
padrão `aarch64-none-linux-gnu-`, GCC como compilador/linker e avisos
`-g -Wall -Werror`.

Para a comparação temporal foram adicionados:

```text
-O3 -g -Wall -Werror -Wextra -Wpedantic -std=c11 -fno-lto
```

A ligação usa `-static`. O compilador realmente usado neste laptop foi:

```text
/opt/Xilinx/Vitis/2024.1/gnu/aarch64/lin/aarch64-linux/bin/aarch64-linux-gnu-gcc
GCC 12.2.0
```

O ELF foi identificado como ARM AArch64 de 64 bits, estaticamente ligado.
Não foi usado um compilador bare metal `aarch64-none-elf-` nem o compilador Nios V.

`multiply_cpu` está em `matrix.c`, compilado separadamente de `main.c`, sem
LTO. Isso preserva as chamadas dentro do laço do benchmark, evitando que o
compilador elimine os cálculos repetidos de matrizes invariantes. A função
continua sendo otimizada internamente com `-O3`, inclusive com vetorização se
o compilador a considerar apropriada; não foi verificado se todas as operações
foram vetorizadas no executável final.

O algoritmo C percorre as matrizes em ordem `i-k-j`, com acesso sequencial a B
e C no laço interno. Uma referência independente em ordem `i-j-k` verifica
a aritmética fora da região cronometrada.

## 10. Metodologia de medição

### 10.1. ARM

O processo fixa sua afinidade no núcleo em que começou. A execução registrada
usou o **núcleo lógico 0**. Em seguida:

1. Aquece o cálculo com 100 chamadas.
2. Estima o custo mínimo de cronometragem com 1.000 pares de leituras de relógio.
3. Mede nove lotes com `CLOCK_MONOTONIC_RAW`.
4. Cada lote executa 10.000 multiplicações completas do mesmo par A/B.
5. Subtrai uma estimativa do custo de cronometragem por lote e divide por 10.000.
6. Confere o resultado de cada lote fora da medição, ordena os tempos e informa
   a mediana e o mínimo.

São 90.000 chamadas cronometradas, além do aquecimento e da referência. Não se
trata de 90.000 pares aleatórios distintos. A medição inclui o pequeno custo
do laço e da chamada e os acessos aos dados em cache, além da aritmética.

### 10.2. FPGA

O ARM não usa seu cronômetro para atribuir tempo ao cálculo da FPGA. O circuito
conta os ciclos de 10.000 operações; após DONE o programa lê **40.000 ciclos**.

```text
tempo do lote = 40.000 / 100.000.000 = 0,0004 s = 400 µs
tempo por multiplicação = 400 µs / 10.000 = 40 ns
```

A frequência de 100 MHz é a configurada no GHRD, declarada em um registrador.
Esse registrador não é um frequencímetro. A contagem veio do circuito executado,
mas sua conversão em nanossegundos usa o clock nominal e é sustentada pela
análise de temporização. Não houve medição externa com osciloscópio.

O programa verifica que os ciclos são `4 × RUNS` e que a frequência/latência
declaradas correspondem à versão esperada. Compara o resultado final do lote
FPGA; não coleta separadamente o resultado de cada uma das 10.000 repetições.

### 10.3. O que fica fora das duas medidas

Geração aleatória, referência de verificação, comparação dos resultados,
impressão, conexão SSH, SCP, programação da FPGA, abertura/mapeamento de
`/dev/mem`, escrita de A/B, START/polling e leitura dos resultados não entram
nos tempos publicados de cálculo. A medição ARM e o contador FPGA usam
mecanismos distintos, descritos acima; não são tempos completos de requisição.

## 11. Testes e implementação no Quartus

### Testes funcionais

- **C:** 104 pares, com zeros, identidade, extremos positivos/negativos e 100
  pares pseudoaleatórios de teste; comparação entre implementação e referência.
- **RTL:** 104 pares; comparação de 64 bits, contagem independente dos ciclos
  busy, múltiplos tamanhos de lote, ID, DONE, escritas durante busy e reset
  durante uma operação.
- **UBSan:** teste numérico C executado sem erro de comportamento indefinido.
- **Placa física:** um par A/B aleatório nesta execução; os 49 resultados finais
  coincidiram entre C e FPGA.

### Resultado físico da compilação

O build completo terminou com sucesso no Quartus em 15/11/2026 às 13:05:28.
O arquivo com SPL foi gerado às 13:05:30.

| Recurso ou verificação | Resultado do sistema completo |
| --- | --- |
| DSPs | **147 / 188 (78%)** |
| ALMs | **18.986 / 46.800 (41%)** |
| Registradores dedicados | 26.893 |
| Memória em blocos | 2.098.688 / 7.331.840 bits (29%) |
| Blocos RAM | 131 / 358 (37%) |
| Clock de cálculo | 100 MHz, período 10 ns |
| Setup do domínio de cálculo | Pass; slack mínimo +2,782 ns |
| Hold do domínio de cálculo | Pass; slack mínimo 0,000 ns |
| Timing Closure | Pass |
| Fmax reportada do domínio de cálculo | 138,54 MHz |

Os recursos incluem o GHRD, não apenas o multiplicador. Para o núcleo isolado,
a síntese estimou 147 DSPs e 9.936 ALMs. A Fmax de 138,54 MHz não foi usada no
experimento; elevar o clock exigiria reconfiguração e nova verificação.

O painel global `Design Closure Summary` marca Fail por avisos que também
aparecem no GHRD 2×2: `RES-50001` (reset assíncrono) e `TMC-20012` (restrição
de saída ausente). As quatro saídas sem restrição são `LED[0]`, `LED[1]`,
`LED[2]` e `LED[7]`. O relatório não encontrou clocks nem entradas sem restrição.
Portanto, não se afirma ausência de todos os avisos de sign-off; setup/hold
dos caminhos analisados passaram, e o teste aritmético físico foi bem-sucedido.

## 12. Reprodução do procedimento

Na raiz do repositório, compile o C no laptop:

```bash
make -C software/MatrixMultiplication7x7 \
  CROSS_COMPILE=/opt/Xilinx/Vitis/2024.1/gnu/aarch64/lin/aarch64-linux/bin/aarch64-linux-gnu-
make -C software/MatrixMultiplication7x7 check
make -C fpga/MatrixMultiplication7x7 sim
```

Adapte o caminho da toolchain em outro laptop. Para preparar o GHRD, configure
as ferramentas e use uma cópia 2×2 já atualizada, preservando a origem:

```bash
export PATH=/home/asaa/altera_pro/26.3/quartus/bin:/home/asaa/altera_pro/26.3/quartus/sopc_builder/bin:$PATH

sh fpga/MatrixMultiplication7x7/scripts/prepare_ghrd.sh \
  /home/asaa/Desktop/Cognus/DE25-Nano/codex/fpga/MatrixMultiplication/build/ghrd_final

sh fpga/MatrixMultiplication7x7/scripts/build_ghrd.sh
```

A preparação é executada uma vez e recusa sobrescrever um diretório existente.
Sem o argumento de origem, usa o ResourcePackage original e pode exigir
upgrades de IP. O script de build gera o sistema, compila `golden_top` e
incorpora o SPL do HPS com `quartus_pfg`; não programa a placa automaticamente.

No Programmer, selecione a FPGA e carregue o **novo** arquivo:

```text
fpga/MatrixMultiplication7x7/build/ghrd_7x7/output_files/golden_top_hps.sof
```

Use a versão com `_hps`: o `.sof` sem SPL pode gerar Error(19192). O procedimento
de permissões USB para Error(18939), Hardware Setup e programação está no
[guia do primeiro projeto](GUIA_MATRIX_MULTIPLICATION.md). A gravação com `.sof`
é volátil; esta experiência não gravou a flash QSPI permanentemente.

No laptop, envie somente o executável:

```bash
scp software/MatrixMultiplication7x7/build/MatrixMultiplication7x7 \
  terasic@192.168.8.2:MatrixMultiplication7x7
ssh terasic@192.168.8.2
```

Na placa, execute:

```bash
sudo ./MatrixMultiplication7x7 0x20011000
```

Um terceiro argumento muda as repetições por lote, até 1.000.000. O modo
`./MatrixMultiplication7x7 --cpu-only` permite medir somente a CPU sem acessar
a FPGA. Para comparação entre núcleos, `taskset -c NUMERO` pode definir a
afinidade antes da execução; esse levantamento não foi realizado neste ensaio.

## 13. Saída original e análise do resultado

A saída abaixo foi fornecida pelo usuário após executar o programa na placa:

```text
Resultados ARM e FPGA coincidem.
ARM, núcleo 0: mediana 1378.20 ns/multiplicação; mínimo 1376.61 ns (9 lotes de 10000).
FPGA: 40.00 ns/multiplicação (4 ciclos/op a 100 MHz; 40000 ciclos no lote).
```

O fator entre a mediana ARM e o tempo FPGA é:

```text
S = 1378,20 ns / 40,00 ns = 34,455 ≈ 34,46 vezes
```

Usando o mínimo ARM, a razão seria aproximadamente 34,42×. A diferença entre
mediana e mínimo ARM foi 1,59 ns, cerca de 0,115% da mediana. Isso mostra
proximidade entre esses dois indicadores nessa execução; sem os nove tempos
brutos, não se calcula desvio-padrão, intervalo de confiança ou distribuição.

O resultado sustenta que, **para este núcleo lógico, código, clock, dados
aquecidos e método de medição**, o circuito executou a aritmética com latência
muito menor que o C otimizado. O ganho decorre de hardware espacial com centenas
de produtos simultâneos e uma árvore de somas registrada, frente ao cálculo
executado por um único núcleo ARM.

## 14. Limitações e próximos experimentos

- **Um ensaio físico registrado:** um par aleatório, repetido para medir. Não
  constitui uma campanha de muitos pares independentes no hardware físico.
- **Sem tempo total da aplicação:** comunicação pode dominar o custo de uma
  matriz 7×7. Não se afirma aceleração de 34,46× incluindo MMIO ou transferências.
- **ARM não exaurido:** não foram comparados todos os núcleos, BLAS, assembly,
  otimizações NEON manuais ou processamento multithread.
- **Clock FPGA nominal:** os 40 ns vêm do contador de ciclos e de 100 MHz;
  não de um instrumento externo nem da Fmax máxima reportada.
- **Sem métricas energéticas:** potência, energia por operação e temperatura
  não foram medidas.
- **Sem reprodução bit a bit do ensaio:** A/B, frequência CPU, nove amostras
  brutas e hashes dos arquivos efetivamente carregados na placa não foram coletados.
- **Avisos do GHRD:** os avisos globais de reset/LED permanecem documentados.

Próximos passos pertinentes seriam registrar os tempos de todos os núcleos,
guardar sementes/amostras para reprodução, medir a latência incluindo comunicação
e experimentar lotes de matrizes distintas ou DMA. Essas modificações não fazem
parte da versão medida neste relatório.

## 15. Evidências e referências

As evidências pequenas foram preservadas no Git, enquanto caches, executáveis
e bitstreams gerados permanecem em diretórios ignorados:

- [Saída original da placa](evidencias/matrix7x7/saida_placa.txt).
- [Resumo extraído dos relatórios locais Quartus](evidencias/matrix7x7/quartus_resumo.txt).
- [Resultados estruturados e hashes dos artefatos locais](evidencias/matrix7x7/resultados.json).

Os hashes identificam os artefatos existentes no laptop ao redigir o relatório;
não comprovam, isoladamente, a identidade dos arquivos usados na placa, pois
seus hashes não foram coletados remotamente. O comando, as métricas e o resultado
físico são os informados pelo usuário na conversa.

- [Software: código, compilação e método de medição](../software/MatrixMultiplication7x7/README.md).
- [FPGA: circuito, registradores e temporização](../fpga/MatrixMultiplication7x7/README.md).
- [Guia do experimento inicial 2×2](GUIA_MATRIX_MULTIPLICATION.md).
- [Altera — recursos Agilex 5 E-Series](https://docs.altera.com/r/docs/762191/current/agilex-5-fpgas-and-socs-device-overview/agilex-5-fpgas-and-socs-e-series).
- [GCC — opções de otimização e LTO](https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html).
