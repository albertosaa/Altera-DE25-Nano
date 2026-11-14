# MatrixMultiplication — circuito FPGA

Este diretório contém o circuito didático e sua integração ao GHRD Terasic.
O [programa C](../../software/MatrixMultiplication/README.md) calcula a referência
e conversa com este circuito pela ponte lightweight HPS-to-FPGA.

O projeto foi executado na placa física em 14/11/2026. Consulte o
[procedimento completo de programação e teste](../../docs/GUIA_MATRIX_MULTIPLICATION.md),
incluindo upgrades de IP, bootloader HPS e permissões do USB-Blaster.

## Funcionamento

`rtl/matrix_mm.v` armazena quatro elementos de A e quatro de B. Ao receber
START, registra em um ciclo quatro somas de dois produtos e ativa DONE.
As entradas ficam estáveis enquanto os produtos combinacionais se propagam;
o ARM escreve todas as entradas antes de escrever START.

Não usamos uma fila, interrupções ou DMA: são poucos registradores e um comando.
DONE permanece ativo até escrever zero no controle, iniciar outra operação ou
aplicar reset. Os resultados permanecem estáveis até outro START ou reset.

Os operandos são de 16 bits com sinal; os produtos têm 32 bits e são estendidos
para 33 bits antes da soma. O atributo `multstyle = "dsp"` sugere DSPs ao Quartus.
A síntese neste laptop confirmou **4 elementos DSP**, com 427 células lógicas
no relatório de síntese do núcleo. Os números finais podem mudar após o fitting
ou a integração no sistema completo. Não se trata de um benchmark de desempenho.

## Mapa de registradores

Todos os acessos do C são palavras de 32 bits alinhadas. O mapa abaixo usa
deslocamentos em **bytes** a partir da base do componente.

| Offset | Registrador | Acesso |
| --- | --- | --- |
| `0x00` | CONTROL: bit 0 START; escrever 0 limpa DONE | escrita |
| `0x04` | STATUS: bit 0 DONE | leitura |
| `0x10`, `0x14`, `0x18`, `0x1c` | A00, A01, A10, A11; usar os 16 bits inferiores | leitura/escrita |
| `0x20`, `0x24`, `0x28`, `0x2c` | B00, B01, B10, B11; usar os 16 bits inferiores | leitura/escrita |
| `0x30`, `0x34` | C00: parte baixa e alta, com extensão de sinal | leitura |
| `0x38`, `0x3c` | C01: parte baixa e alta | leitura |
| `0x40`, `0x44` | C10: parte baixa e alta | leitura |
| `0x48`, `0x4c` | C11: parte baixa e alta | leitura |
| `0x50` | ID fixo `0x4d4d0001` | leitura |

No Verilog, `address` está em **palavras**, não bytes: `address=4` corresponde
a `0x10`. O componente Avalon-MM declara `addressUnits WORDS`, cinco bits de
endereço e uma janela de 128 bytes. O Platform Designer adapta o endereçamento.

## Simular no laptop

Com Icarus Verilog instalado, na raiz do repositório:

```bash
make -C fpga/MatrixMultiplication sim
```

O testbench `sim/tb_matrix_mm.sv` escreve e lê os mesmos registradores usados
pelo C. Verifica o exemplo, zeros, extremos positivos/negativos e 100 pares
pseudoaleatórios, além de ID, DONE e reset. Não usa IP proprietário para simular.

## Abrir e estudar no Quartus

Abra `quartus/MatrixMultiplication.qpf` no Quartus Prime Pro com suporte Agilex 5.
O dispositivo `A5EB013BB23BE4SCS` e a família foram copiados de
`ResourcePackage/Demonstration/SoC_FPGA/GHRD/golden_top.qsf`.

1. Execute Analysis & Elaboration para conferir portas e hierarquia.
2. Abra RTL Viewer, em Tools → Netlist Viewers, para estudar multiplicadores,
   somadores e registradores.
3. Execute a síntese e consulte o relatório de recursos e o Technology Map
   Viewer para verificar os DSPs inferidos.

No terminal, com as ferramentas no PATH:

```bash
cd fpga/MatrixMultiplication/quartus
quartus_syn MatrixMultiplication --analysis_and_elaboration
quartus_syn MatrixMultiplication
```

Os relatórios ficam em `../build/output_files/`. A síntese foi validada no
Quartus Pro 26.3. O projeto isolado **não é um projeto para programar a placa**:
suas portas são os sinais internos Avalon-MM, sem pinagem de placa nem HPS.
O aviso de Reset Release IP nesse projeto isolado é esperado; a configuração
real deve usar a infraestrutura completa do GHRD, com clocks/resets da placa.

## Integrar ao GHRD da demonstração

`scripts/prepare_ghrd.sh` copia o GHRD para `build/ghrd_final`, adiciona o componente
ao catálogo local e chama `scripts/integrate.tcl`. A demonstração original
permanece intacta. Não copiamos os 91 MB do GHRD para o histórico Git: o script
recria a cópia de trabalho a partir do ResourcePackage local.

Neste laptop, configure o PATH:

```bash
export PATH=/home/asaa/altera_pro/26.3/quartus/bin:/home/asaa/altera_pro/26.3/quartus/sopc_builder/bin:$PATH
```

Na raiz do repositório:

```bash
sh fpga/MatrixMultiplication/scripts/prepare_ghrd.sh
```

Também é possível passar o diretório do GHRD como primeiro argumento e um
diretório de saída absoluto como segundo argumento.
O script recusa sobrescrever uma cópia de trabalho existente. Se uma tentativa
for interrompida, confira essa cópia antes de preparar outra.

O script conecta no `peripheral_subsys`:

| Origem existente no GHRD | Porta do novo componente |
| --- | --- |
| `periph_clk.out_clk` | `matrix_0.clock` |
| `periph_rst_in.out_reset` | `matrix_0.reset` |
| `pb_cpu_0.m0` | `matrix_0.s0`, base relativa `0x00010100` |

Esses nomes foram obtidos da demonstração, não de um projeto Cyclone V.
O `qsys_top.qsys` conecta `subsys_hps.lwhps2fpga` ao subsistema de periféricos
com deslocamento zero. O offset escolhido não sobrepõe os periféricos originais
do `pb_cpu_0`, localizados próximos a `0x00010000`.

Abra a cópia `build/ghrd_final/golden_top.qpf`, depois o Platform Designer e confira
`peripheral_subsys/peripheral_subsys.qsys`. O componente aparece como
**MatrixMultiplication 2x2**. Se necessário, adicione
`build/ghrd_final/custom_ip/matrix/ip` aos caminhos de busca do catálogo de IP.

Antes de usar na placa:

1. Confira o Address Map e a propagação da janela pelo `pb_cpu_0` até o HPS.
2. Atualize IPs se a versão do Quartus solicitar. A demonstração usa IPs 25.1,
   enquanto o Quartus instalado é 26.3; preserve o original para comparação.
3. Gere o HDL do subsistema alterado e de `qsys_top` no Platform Designer.
4. Compile o projeto completo `golden_top`, incluindo análise de temporização.
5. Programe a FPGA usando o fluxo de configuração HPS/FPGA compatível com o
   boot da imagem instalada. Os arquivos `sof_with_hps.bat` e `sof_to_jic.bat`
   da demonstração são referências desse fluxo, não scripts Linux deste projeto.
6. Confirme clock, reset e ponte lightweight habilitados antes do acesso MMIO.
7. Envie o ELF do C e execute-o com a base física confirmada.

Não use o `.sof` original em `output_files` da cópia como se ele contivesse o
novo componente: é um resultado antigo fornecido pela demonstração.

O endereço físico usado no C é a **base física da ponte lightweight no HPS**
mais `0x00010100`, desde que os offsets do restante do sistema permaneçam
como no GHRD. O endereço relativo validado (`0x00010100`) fica dentro
da janela de 17 bits (`0x00000` a `0x1ffff`) do `pb_cpu_0.m0`. Confira o mapa do Agilex 5 e o sistema gerado; o programa recebe
essa base explicitamente para evitar aplicar endereços de outra família.

## Validação

O núcleo foi simulado e sintetizado. O script foi validado numa cópia limpa do
GHRD e o HDL do subsistema de periféricos com o multiplicador foi gerado com
sucesso no Platform Designer 26.3. Há avisos de versão/configuração dos IPs
originais; a geração terminou sem erros. Após os upgrades necessários, o projeto
completo foi compilado com sucesso e programado usando `golden_top_hps.sof`,
com o SPL incorporado. O teste físico confirmou os resultados `19, 22, 43, 50`
iguais aos do ARM, acessando o componente em `0x20010100`.

O uso de 4 DSPs foi medido na síntese do núcleo isolado. A verificação física
usou o exemplo fixo; os negativos e extremos foram testados em simulação.

## Referências

- Makefile Linux: `ResourcePackage/Demonstration/SoC/gsensor/Makefile`.
- Toolchain Arm: `ResourcePackage/Demonstration/SoC_FPGA/GHRD/software/hps_debug/build.sh`.
- Integração: `GHRD/qsys_top.qsys` e `GHRD/peripheral_subsys/peripheral_subsys.qsys`.
- [Agilex 5 — espaços de endereçamento HPS](https://docs.altera.com/r/docs/814346/26.1.1/hard-processor-system-technical-reference-manual-agilex-5-socs/total-address-spaces).
- [Quartus — estilo de multiplicadores inferidos](https://docs.altera.com/r/docs/683283/18.1/intel-quartus-prime-standard-edition-user-guide-design-compilation/multiplier-style-for-inferred-multipliers).
