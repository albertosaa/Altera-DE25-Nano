# MatrixMultiplication: do código à execução na DE25-Nano

Procedimento realizado e validado em **14/11/2026**: compilação no laptop,
programação da FPGA pelo USB-Blaster e execução do programa C pelo SSH Ethernet.

## 1. Objetivo e resultado

O ARM calcula em C o produto de duas matrizes 2×2. Em seguida escreve as mesmas
entradas em registradores da FPGA, solicita o cálculo, lê os resultados e compara.

```text
A = [1 2]    B = [5 6]    A × B = [19 22]
    [3 4]        [7 8]            [43 50]
```

O teste físico retornou `SUCESSO: ARM e FPGA concordam.`

| Parte | Onde fica | Como chega à placa |
| --- | --- | --- |
| Programa C | `software/MatrixMultiplication/` | Somente o executável é copiado por SCP |
| Circuito Verilog | `fpga/MatrixMultiplication/rtl/` | Compilado no Quartus e carregado pelo USB-Blaster |
| Integração HPS/FPGA | Cópia local do GHRD em `fpga/MatrixMultiplication/build/ghrd_final/` | Incluída no bitstream do projeto completo |

O programa C não configura automaticamente a FPGA. As duas etapas de carga são
separadas. A multiplicação no ARM usa C padrão; o acesso aos registradores usa
as interfaces Linux `open` e `mmap` sobre `/dev/mem`.

## 2. Ambiente e pré-requisitos

- Placa Terasic DE25-Nano, Agilex 5, dispositivo `A5EB013BB23BE4SCS`.
- Linux da placa: `6.12.11-gd7d192a9ddd9`; usuário `terasic`.
- Laptop Linux com Quartus Prime Pro **26.3.0 Build 114** e suporte ao dispositivo.
- Demonstrações originais em `../ResourcePackage/Demonstration/`, relativamente
  à raiz deste repositório. O GHRD fornecido foi criado no Quartus 25.1.
- Toolchain AArch64 Linux; compilação deste teste com GCC 12.2.0 do Vitis.
- USB-Blaster conectado ao laptop, placa alimentada e conexão SSH por Ethernet.

Neste guia, os comandos partem da raiz do repositório, exceto onde indicado.
O caminho usado neste laptop é `/home/asaa/Desktop/Cognus/DE25-Nano/codex`.
Adapte caminhos de instalação em outro computador.

## 3. Conexão Ethernet direta, sem roteador

O procedimento completo, incluindo picocom e a alternativa USB, está no
[guia de acesso SSH](GUIA_SSH_USB_DE25_NANO.md).

Conecte a placa ao laptop por cabo Ethernet. Configure inicialmente a placa
pelo picocom ou por uma conexão já disponível.

**Na placa:**

```bash
sudo ip addr add 192.168.8.2/24 dev eth0
sudo ip link set eth0 up
```

**No laptop:**

```bash
sudo ip addr add 192.168.8.1/24 dev enp0s31f6
sudo ip link set enp0s31f6 up
ping -c 3 192.168.8.2
ssh terasic@192.168.8.2
```

Confira o nome da interface Ethernet com `ip -br addr` em outro laptop.
Não é necessário gateway ou DNS. Os endereços são temporários. Se `ip addr add`
retornar `File exists`, confira se o endereço correto já está configurado.

## 4. Compilar e testar o programa C no laptop

O Makefile segue a demonstração `SoC/gsensor`: `ARCH=arm64`, prefixo padrão
`aarch64-none-linux-gnu-`, GCC como compilador/linker e `-g -Wall -Werror`.
Adiciona C11 e avisos extras. A ligação estática evita instalar bibliotecas
adicionais na placa.

Com a toolchain das demonstrações no PATH:

```bash
make -C software/MatrixMultiplication
```

Neste laptop foi usado o compilador AArch64 Linux já instalado pelo Vitis:

```bash
make -C software/MatrixMultiplication \
  CROSS_COMPILE=/opt/Xilinx/Vitis/2024.1/gnu/aarch64/lin/aarch64-linux/bin/aarch64-linux-gnu-

file software/MatrixMultiplication/build/MatrixMultiplication
```

A saída de `file` foi ELF de 64 bits, ARM AArch64, estaticamente ligado.
Não use um compilador `aarch64-none-elf-` bare metal nem um compilador Nios V.
Ao trocar de compilador ou opções, execute `make clean` nesse diretório primeiro.

Teste nativo no laptop, sem acessar a FPGA:

```bash
make -C software/MatrixMultiplication check
```

## 5. Simular e visualizar o circuito

```bash
make -C fpga/MatrixMultiplication sim
```

A simulação com Icarus Verilog passou em **104 pares de matrizes**, incluindo
negativos, zeros, extremos de 16 bits, além de ID, DONE e reset.

Para estudar o circuito isolado, abra no Quartus:

```text
fpga/MatrixMultiplication/quartus/MatrixMultiplication.qpf
```

Execute Analysis & Elaboration e abra o RTL Viewer. Após a síntese, consulte o
Technology Map Viewer e o relatório de recursos. A síntese isolada confirmou
**4 elementos DSP**. Esse projeto isolado serve para estudo: não contém o HPS
nem a pinagem completa da placa e não é o projeto a carregar no Programmer.

## 6. Preparar a cópia do GHRD

Configure os caminhos do Quartus no terminal do laptop:

```bash
export PATH=/home/asaa/altera_pro/26.3/quartus/bin:/home/asaa/altera_pro/26.3/quartus/sopc_builder/bin:$PATH
```

Prepare a integração, uma vez:

```bash
sh fpga/MatrixMultiplication/scripts/prepare_ghrd.sh
```

O script copia a demonstração original, adiciona o componente e conecta:

| Origem do GHRD | Destino |
| --- | --- |
| `periph_clk.out_clk` | `matrix_0.clock` |
| `periph_rst_in.out_reset` | `matrix_0.reset` |
| `pb_cpu_0.m0` | `matrix_0.s0`, offset `0x00010100` |

O offset está dentro da janela de 17 bits da ponte do subsistema e não se
sobrepõe aos periféricos originais. O script recusa sobrescrever uma cópia já
existente. No laptop deste teste ela já está preparada: basta abri-la.

## 7. Abrir o sistema correto e atualizar IPs

No Quartus, abra:

```text
fpga/MatrixMultiplication/build/ghrd_final/golden_top.qpf
```

No Platform Designer, abra explicitamente o sistema `qsys_top.qsys` dessa mesma
pasta. Se ele abrir sem sistema e mostrar a mensagem “Create or specify a
Platform Designer system”, use File → Open e selecione esse `.qsys`.

Outra opção, no terminal do laptop:

```bash
cd fpga/MatrixMultiplication/build/ghrd_final
qsys-edit qsys_top.qsys --quartus-project=golden_top.qpf
```

Para ver o multiplicador, abra `peripheral_subsys/peripheral_subsys.qsys`.
O componente é `matrix_0`, com nome de catálogo **MatrixMultiplication 2x2**.

Foram necessários upgrades de IPs entre a demonstração 25.1 e o Quartus 26.3.
Faça-os somente na cópia de trabalho, confira mensagens e preserve os parâmetros
do HPS/memória. Depois confirme que o módulo e o offset continuam corretos e
gere novamente o HDL dos sistemas atualizados, incluindo `qsys_top`.

## 8. Compilar o projeto completo

No projeto `golden_top`, execute Processing → Start Compilation. Confira o
relatório final antes de programar. Neste teste, `golden_top.flow.rpt` registrou
`Flow Status: Successful` em 14/11/2026, às 16:47:36.

O resultado da compilação é:

```text
fpga/MatrixMultiplication/build/ghrd_final/output_files/golden_top.sof
```

A cópia inicial do GHRD também traz `.sof` e `.jic` antigos. A presença de um
arquivo em `output_files` não confirma que ele contenha o multiplicador: use
o arquivo produzido pela compilação bem-sucedida do projeto modificado.

## 9. Incorporar o bootloader HPS ao SOF

O `.sof` com HPS precisa das informações do bootloader. Sem elas, o Programmer
apresentou **Error(19192): HPS is present but bootloader information is missing**.

Na pasta `fpga/MatrixMultiplication/build/ghrd_final`, execute no laptop:

```bash
quartus_pfg -c output_files/golden_top.sof \
  output_files/golden_top_hps.sof \
  -o hps_path=software/u-boot/spl/u-boot-spl-dtb.hex
```

Esse comando adapta o `sof_with_hps.bat` da demonstração para Linux. O SPL é o
fornecido no GHRD utilizado neste teste. Repita a conversão após uma nova
compilação, para que o arquivo com HPS corresponda ao circuito mais recente.

O arquivo a selecionar no Programmer é **`golden_top_hps.sof`**.

## 10. Permissões do USB-Blaster no laptop

O Programmer apresentou **Error(18939): Insufficient port permissions**.
O `lsusb` identificou a placa como `09fb:6026 Altera DE25-Nano`.

Para permitir o acesso USB, execute no laptop:

```bash
echo 'SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="09fb", ATTR{idProduct}=="6026", MODE="0666"' | sudo tee /etc/udev/rules.d/92-de25-nano.rules

sudo udevadm control --reload-rules
```

Desconecte e reconecte somente o cabo USB-Blaster, mantendo a alimentação da
placa. Feche e reabra o Programmer. A regra permanece após reiniciar o laptop.
Ela concede acesso USB de leitura/escrita aos usuários locais para esse VID/PID.

## 11. Programar a FPGA

No Quartus, abra Tools → Programmer:

1. Em Hardware Setup, selecione o USB-Blaster.
2. Use Auto Detect para identificar a cadeia JTAG.
3. Selecione a FPGA e use Change File.
4. Escolha o novo `output_files/golden_top_hps.sof` da cópia do GHRD.
5. Marque Program/Configure e clique em Start.
6. Aguarde a conclusão sem erros, em 100%.

Este procedimento carrega o `.sof` na FPGA; não foi necessário gravar a flash
com `.jic`. O circuito precisará ser recarregado após desligar a placa, salvo
se posteriormente for configurado um fluxo de inicialização permanente.

A programação pode interromper o HPS e o SSH. Aguarde o Linux iniciar e
reconecte. Se necessário, recupere o console pelo picocom e reconfigure os IPs
temporários da Ethernet.

## 12. Copiar e testar o executável na placa

Na raiz do repositório, no laptop:

```bash
scp software/MatrixMultiplication/build/MatrixMultiplication \
  terasic@192.168.8.2:MatrixMultiplication

ssh terasic@192.168.8.2
```

Somente o executável é copiado; a placa não compila o projeto.

Na placa, teste inicialmente sem acessar o hardware:

```bash
./MatrixMultiplication --cpu-only
```

O teste retornou `19, 22, 43, 50` corretamente.

## 13. Endereço físico e diagnóstico do Linux

O endereço validado neste sistema é:

```text
Base física da ponte lightweight HPS-to-FPGA: 0x20000000
Offset do multiplicador no sistema:         +0x00010100
Base física do multiplicador:               0x20010100
```

O programa recebe essa base como argumento e verifica o ID `0x4d4d0001` no
offset `0x50` antes de escrever as entradas.

Durante o diagnóstico, estes comandos não mostraram mapas/pontes nomeados:

```bash
sudo cat /proc/iomem | grep -Ei 'fpga|bridge'
ls /sys/class/fpga_bridge
```

Isso não impediu o funcionamento: a ausência de uma região nomeada ou de uma
ponte nessa classe do sysfs não comprova que o acesso pelo HPS esteja desativado.
O log confirmou o gerenciador FPGA:

```text
fpga_manager fpga0: Stratix10 SOC FPGA Manager registered
of-fpga-region fpga-region: FPGA Region probed
```

Esses nomes apareceram na própria imagem Agilex 5; não significam que a placa
seja Stratix 10. O registro do gerenciador, isoladamente, também não prova que
o multiplicador esteja carregado.

Comandos úteis de diagnóstico, executados na placa:

```bash
sudo head -40 /proc/iomem
find -L /proc/device-tree -iname '*bridge*' -o -iname '*fpga*'
sudo dmesg | grep -Ei 'fpga|bridge|firmware'
```

O `-L` faz o `find` percorrer o link simbólico `/proc/device-tree`.

Use `0x20010100` com o projeto e o mapeamento descritos aqui. Em outro sistema,
confira o mapa antes de acessar `/dev/mem`. Uma leitura em uma ponte que não
responde pode bloquear; o timeout do programa cobre a espera por DONE, não
consegue cancelar uma transação MMIO já bloqueada.

## 14. Comparação ARM × FPGA: teste físico realizado

Na placa, após carregar o circuito:

```bash
sudo ./MatrixMultiplication 0x20010100
```

Saída real informada pelo usuário:

```text
A = [[1, 2], [3, 4]]; B = [[5, 6], [7, 8]]
Resultado no ARM:
[ 19  22 ]
[ 43  50 ]
Resultado na FPGA:
[ 19  22 ]
[ 43  50 ]
SUCESSO: ARM e FPGA concordam.
```

Esse teste valida o exemplo na placa física: executável AArch64, cálculo no
ARM, acesso aos registradores pela ponte, cálculo na FPGA e leitura/comparação.
Os casos negativos e extremos foram cobertos na simulação, não no teste físico
de matrizes fixas acima. Não foi realizada medição de desempenho.

## 15. O que permanece temporário

- IPs fixos adicionados com `ip addr add`.
- Circuito carregado por `.sof`, sem gravação permanente da flash.
- Configuração de rede USB do guia de SSH, se utilizada.

A regra udev e o executável copiado ao diretório do usuário ficam armazenados
em seus respectivos sistemas. Fontes, scripts e documentação são versionados;
`build/`, caches, executáveis e bitstreams ficam fora do Git e são regenerados
com as ferramentas e o ResourcePackage local.

## Referências

- [Guia de acesso SSH USB/Ethernet](GUIA_SSH_USB_DE25_NANO.md).
- [Software e cross-compiling](../software/MatrixMultiplication/README.md).
- [Hardware, registradores e simulação](../fpga/MatrixMultiplication/README.md).
- GHRD local: `../ResourcePackage/Demonstration/SoC_FPGA/GHRD/`.
- [Agilex 5 — mapa da ponte lightweight](https://docs.altera.com/r/docs/814346/26.1.1/hard-processor-system-technical-reference-manual-agilex-5-socs/general-purpose-address-space).
- [USB-Blaster III — instalação no Linux](https://docs.altera.com/r/docs/864466/current/usb-blaster-iii-fpga-development-cable-user-guide/installing-the-usb-blaster-iii-fpga-development-cable-on-linux-systems).
