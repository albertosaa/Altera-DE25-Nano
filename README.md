# Projeto DE25-Nano

<p align="center">
<img src="img/DE-25.jpg" alt="DE25-nano" width="40%" /> 
</p>


Código FPGA, software Linux e documentação para a Terasic DE25-Nano.

O acesso SSH por USB e Ethernet direta foi validado. O primeiro projeto é
[MatrixMultiplication](software/MatrixMultiplication/README.md): multiplicação
de matrizes 2×2 no ARM e na FPGA, com comparação dos resultados.
O teste na placa física passou. Veja o
[guia completo de compilação, programação e execução](docs/GUIA_MATRIX_MULTIPLICATION.md).

A versão [MatrixMultiplication7x7](software/MatrixMultiplication7x7/README.md)
usa matrizes aleatórias com sinal e compara tempos de cálculo no ARM e na FPGA,
com contador interno de ciclos no circuito.
O teste físico confirmou resultados iguais, com mediana de **1.378,20 ns no
ARM** e **40 ns na FPGA**, excluindo comunicação. O
[relatório do experimento 7×7](docs/RELATORIO_MATRIX_MULTIPLICATION_7x7.md)
inclui a escolha da dimensão, a análise de DSPs e o método de medição.

## Estrutura

- `docs/`: configuração e documentação da placa.
- `fpga/rtl/`: fontes HDL.
- `fpga/constraints/`: pinos e restrições de tempo.
- `fpga/sim/`: testbenches e simulação.
- `fpga/quartus/`: projeto Quartus e configurações reproduzíveis.
- `software/`: programas para o Linux da placa.
- `scripts/`: automação de compilação e transferência.

## Acesso à placa

Consulte o [guia SSH por USB e Ethernet direta](docs/GUIA_SSH_USB_DE25_NANO.md).

Com a rede USB configurada, conecte a porta HPS USB ao computador e execute:

```bash
ssh terasic@192.168.7.2
```

A configuração USB documentada ainda é temporária.

## Ambiente validado

- Placa: Terasic DE25-Nano.
- Kernel Linux da placa: `6.12.11-gd7d192a9ddd9`.
- Computador de desenvolvimento: Linux.
- Quartus Prime Pro 26.3.0 Build 114; GHRD original da demonstração 25.1.
- Cross-compiling validado com GCC 12.2.0 AArch64 Linux (Vitis).
- Versão/distribuição da imagem Linux: a registrar.

## Organização do desenvolvimento

Versionar fontes, testes, scripts, configurações e documentação. Manter caches e
resultados de compilação fora do histórico. Registrar instruções de compilação e
execução junto com cada aplicação adicionada.
