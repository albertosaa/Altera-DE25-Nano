# Acesso SSH à Terasic DE25-Nano por USB e Ethernet

Este guia registra os procedimentos que funcionaram em um computador Linux e uma DE25-Nano com Linux instalado. O objetivo é acessar a placa por SSH sem precisar de roteador, usando rede USB ou um cabo Ethernet direto.

As etapas 1 a 9 descrevem a conexão por USB. A seção 10 apresenta a conexão Ethernet direta, sem roteador, validada em 14/11/2026. A seção 11 descreve a alternativa com roteador, ainda não testada neste procedimento.

## 1. Materiais e portas utilizadas

- DE25-Nano alimentada e com Linux inicializando.
- Computador Linux com cliente SSH.
- Dois cabos USB de dados: um para o console e outro para a rede USB durante a configuração.
- Senha do usuário `terasic` da placa.

As portas têm funções diferentes:

| Porta da placa | Função neste procedimento |
| --- | --- |
| USB Blaster/UART | Programação da FPGA e console serial pelo picocom |
| HPS USB | Rede USB usada pelo SSH |

Depois de configurar a rede, basta manter o cabo HPS USB para usar SSH, desde que a placa continue alimentada corretamente. O cabo de console pode ser retirado quando não for mais necessário.

## 2. Verificar se o computador detecta a placa

Conecte o cabo à porta USB Blaster/UART. No terminal **do computador**, execute:

```bash
lsusb
ip -br addr
ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
```

No caso testado, apareceu:

```text
ID 09fb:6026 Altera DE25-Nano
/dev/ttyUSB0
/dev/ttyUSB1
```

Nesse momento ainda não havia uma interface de rede USB. A presença da placa no `lsusb` não significa que o SSH por USB já esteja disponível.

## 3. Abrir o console serial com picocom

O picocom é um terminal serial: permite digitar comandos no Linux da placa pelo USB, sem uma conexão de rede.

No Ubuntu/Debian, se necessário, instale-o **no computador**:

```bash
sudo apt install picocom
```

Abra a porta serial:

```bash
sudo picocom -b 115200 /dev/ttyUSB0
```

Pressione Enter para ver o prompt e faça login, se solicitado. No caso testado, o console funcionou na `ttyUSB0`, com o usuário `terasic`:

```text
terasic@localhost:~$
```

Se não aparecer um console legível, saia com **Ctrl+A**, solte e pressione **Ctrl+X**. Depois tente `/dev/ttyUSB1`. A numeração pode variar entre computadores.

Para colar comandos no terminal, use **Ctrl+Shift+V**, **Shift+Insert** ou o menu de contexto → Colar. `Ctrl+V` normalmente não cola em terminais Linux. Ao digitar a senha do `sudo`, nenhum caractere aparece na tela.

## 4. Verificar usuário, rede e servidor SSH

Execute **na placa, pelo picocom**:

```bash
whoami
ip -br addr
ss -lnt | grep ':22'
```

Resultados encontrados:

- Usuário: `terasic`.
- Interface `eth0`: desativada e sem IP.
- Servidor SSH: já escutando na porta 22, em IPv4 e IPv6.

Portanto, não foi necessário instalar nem ativar um servidor SSH. Faltava criar a rede USB. Se outra imagem Linux não apresentar um serviço na porta 22, será necessário configurar o servidor SSH nessa imagem antes de prosseguir com o acesso remoto.

## 5. Verificar o suporte à rede USB no kernel

Execute **na placa**:

```bash
uname -r
ls /sys/class/udc
ls /sys/class/net
sudo modprobe g_ether
```

No caso testado:

```text
Kernel: 6.12.11-gd7d192a9ddd9
Controlador USB: 10b00000.usb
Interfaces iniciais: eth0 lo
```

O comando `modprobe g_ether` falhou:

```text
modprobe: FATAL: Module g_ether not found in directory /lib/modules/6.12.11-gd7d192a9ddd9
```

Esse erro não impediu a configuração: usamos USB Gadget ConfigFS como alternativa.

Execute **na placa**:

```bash
sudo modprobe libcomposite
ls -ld /sys/kernel/config/usb_gadget
zcat /proc/config.gz 2>/dev/null | grep -E 'CONFIG_USB_(CONFIGFS|CONFIGFS_ECM|F_ECM|LIBCOMPOSITE|ETH)='
```

Se `/proc/config.gz` não fornecer a configuração, tente:

```bash
grep -E 'CONFIG_USB_(CONFIGFS|CONFIGFS_ECM|F_ECM|LIBCOMPOSITE|ETH)=' /boot/config-$(uname -r)
```

O carregamento de `libcomposite` funcionou, o diretório `usb_gadget` existia e apareceram estas opções:

```text
CONFIG_USB_LIBCOMPOSITE=m
CONFIG_USB_F_ECM=m
CONFIG_USB_CONFIGFS=m
CONFIG_USB_CONFIGFS_ECM=y
```

Esses resultados confirmaram o suporte necessário para os próximos passos. Se forem diferentes, verifique a configuração da imagem Linux antes de continuar.

## 6. Criar a interface de rede USB na placa

Execute o bloco abaixo **na placa, pelo picocom**, uma única vez nesta inicialização. Ele cria um dispositivo USB Ethernet ECM e atribui à placa o IP `192.168.7.2/24`.

O nome `10b00000.usb` deve corresponder ao controlador mostrado em `/sys/class/udc`. Os identificadores USB abaixo foram usados nesta configuração local de teste.

```bash
sudo bash <<'EOF'
set -e
cd /sys/kernel/config/usb_gadget
mkdir ssh_usb
cd ssh_usb

echo 0x1d6b > idVendor
echo 0x0104 > idProduct

mkdir -p strings/0x409
echo DE25Nano001 > strings/0x409/serialnumber
echo Terasic > strings/0x409/manufacturer
echo "DE25 USB Network" > strings/0x409/product

mkdir -p configs/c.1/strings/0x409
echo "USB Ethernet" > configs/c.1/strings/0x409/configuration

mkdir functions/ecm.usb0
echo 02:25:00:00:00:01 > functions/ecm.usb0/dev_addr
echo 02:25:00:00:00:02 > functions/ecm.usb0/host_addr
ln -s functions/ecm.usb0 configs/c.1/

echo 10b00000.usb > UDC
ip addr add 192.168.7.2/24 dev usb0
ip link set usb0 up
EOF
```

O bloco usa `set -e` para parar se algum comando falhar. Se houver erro, registre a mensagem antes de tentar novamente: o bloco não foi preparado para ser repetido sobre uma configuração já criada. Por exemplo, `mkdir ssh_usb` falhará se esse diretório já existir.

Para conferir:

```bash
ip -br addr usb0
```

## 7. Conectar a porta HPS USB ao computador

Mantenha o cabo do console conectado e conecte um segundo cabo USB de dados entre a porta **HPS USB** da placa e o computador.

Abra outro terminal **no computador** e execute:

```bash
ip -br addr
```

No caso testado, surgiu:

```text
enx022500000002  UP  fe80::c4a6:abe7:a9c0:3134/64
```

Esse era o adaptador de rede USB. O endereço IPv4 ainda precisava ser atribuído. O nome da interface pode variar: use o que aparecer no seu computador nos comandos seguintes.

Se não aparecer uma nova interface, confira se o cabo transmite dados, se está conectado à porta HPS USB e se o bloco da etapa anterior terminou sem erros.

## 8. Configurar o IP do computador e conectar por SSH

Execute **no computador**, substituindo o nome da interface se necessário:

```bash
sudo ip addr add 192.168.7.1/24 dev enx022500000002
sudo ip link set enx022500000002 up
ssh terasic@192.168.7.2
```

Na primeira conexão, o SSH solicitará a confirmação da chave do servidor. Confirme com `yes` após conferir que o destino é a sua placa e digite a senha de `terasic`.

**O acesso SSH funcionou com esta configuração.**

| Equipamento | Interface | IPv4 |
| --- | --- | --- |
| Computador | `enx022500000002` no caso testado | `192.168.7.1/24` |
| DE25-Nano | `usb0` | `192.168.7.2/24` |

Não foi necessário configurar gateway ou DNS para essa conexão direta.

Para acessos seguintes, enquanto a configuração estiver ativa:

```bash
ssh terasic@192.168.7.2
```

Para fechar o SSH, execute `exit`. Para sair do picocom, use **Ctrl+A**, depois **Ctrl+X**. Sair do picocom não desliga a placa nem encerra a rede USB.

## 9. Persistência: o que ainda não foi configurado

**A configuração realizada é temporária.** O gadget ConfigFS e o endereço da placa precisam ser recriados após reiniciar a placa. O endereço atribuído manualmente no computador também pode ser perdido após reinicialização ou reconfiguração da interface.

Discutimos tornar a configuração permanente, mas essa etapa não foi executada nem validada. Para fazê-la, será necessário:

1. Criar um serviço de inicialização na placa que configure o gadget e o IP.
2. Salvar uma conexão de rede no computador com o IPv4 `192.168.7.1/24`.

Os diagnósticos solicitados para preparar essa etapa foram:

**Na placa:**

```bash
ps -p 1 -o comm=
command -v ip
```

**No computador:**

```bash
nmcli -t -f NAME,DEVICE connection show --active
```

As saídas desses comandos ainda não foram coletadas neste procedimento.

## 10. SSH por Ethernet direto, sem roteador

A rede USB é independente da Ethernet. Não é necessário repetir a configuração de gadget USB para usar a porta Ethernet.

**O acesso SSH com um cabo Ethernet diretamente entre a placa e o laptop foi testado e funcionou.** O servidor SSH da placa já estava ativo.

### 10.1. Conectar o cabo

Mantenha a placa alimentada e conecte um cabo Ethernet entre a porta Ethernet da DE25-Nano e a porta Ethernet do laptop. Use inicialmente o picocom ou o SSH USB para configurar o lado da placa.

### 10.2. Configurar a placa

Execute **na placa**:

```bash
sudo ip addr add 192.168.8.2/24 dev eth0
sudo ip link set eth0 up
```

### 10.3. Configurar o laptop

Execute **no laptop**:

```bash
sudo ip addr add 192.168.8.1/24 dev enp0s31f6
sudo ip link set enp0s31f6 up
```

`enp0s31f6` é a interface Ethernet do laptop utilizado. Em outro computador, consulte `ip -br addr` e substitua pelo nome da interface Ethernet correspondente.

### 10.4. Testar e acessar por SSH

Execute **no laptop**:

```bash
ping -c 3 192.168.8.2
ssh terasic@192.168.8.2
```

Informe a senha do usuário `terasic`. Na primeira conexão com esse endereço, confira o destino e confirme a chave do servidor se solicitado.

| Equipamento | Interface | IPv4 |
| --- | --- | --- |
| Laptop | `enp0s31f6` no caso testado | `192.168.8.1/24` |
| DE25-Nano | `eth0` | `192.168.8.2/24` |

Não é necessário configurar gateway ou DNS para essa conexão direta. A faixa `192.168.8.0/24` é diferente da rede USB (`192.168.7.0/24`) e do Wi-Fi utilizado (`192.168.1.0/24`). Em outro ambiente, escolha uma faixa que não conflite com as redes existentes.

Depois de estabelecer o SSH pela Ethernet, a conexão USB não é necessária para transportar essa sessão; mantenha a alimentação da placa.

### 10.5. Persistência e repetição dos comandos

**Os endereços foram configurados temporariamente.** Podem ser perdidos ao reiniciar os equipamentos ou reconfigurar as interfaces. A configuração Ethernet permanente ainda não foi realizada.

Se repetir `ip addr add` e aparecer `RTNETLINK answers: File exists`, confira se o endereço já está presente com `ip -br addr`. Se o IP correto estiver configurado, prossiga para o teste e o SSH sem adicioná-lo novamente.

## 11. Alternativa: SSH por Ethernet com roteador

Se o Linux da placa estiver configurado para DHCP, ao conectar a placa a um roteador ela poderá receber um IP automaticamente. O computador deve estar na mesma rede, por cabo ou Wi-Fi.

Para consultar o IP, execute **na placa**, usando o console serial ou o SSH USB:

```bash
ip -br addr eth0
```

Depois conecte **pelo computador**:

```bash
ssh terasic@IP_DA_ETHERNET
```

Se a Ethernet estiver desativada e o sistema tiver o cliente `dhclient`, os comandos discutidos foram:

```bash
sudo ip link set eth0 up
sudo dhclient eth0
ip -br addr eth0
```

Essa alternativa com roteador e DHCP não foi testada neste procedimento. O IP usado no comando SSH deve ser o atribuído à interface Ethernet da placa nessa rede.

## Referências

- [Terasic — DE25-Nano: características e interfaces](https://www.terasic.com.tw/cgi-bin/page/archive.pl?CategoryNo=123&Language=English&No=1384&PartNo=2)
- [Linux Kernel — USB Gadget configurado por ConfigFS](https://www.kernel.org/doc/html/latest/usb/gadget_configfs.html)
- [Linux Kernel — testes e funções USB Gadget, incluindo ECM](https://docs.kernel.org/usb/gadget-testing.html)
