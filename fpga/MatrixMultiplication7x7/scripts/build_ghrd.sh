#!/bin/sh
# Compila e gera o SOF com bootloader. Não programa a placa nem grava a flash.
# Requer quartus/bin e quartus/sopc_builder/bin no PATH.
set -eu
project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ghrd=${1:-"$project/build/ghrd_7x7"}
test -f "$ghrd/golden_top.qpf"
cp "$project/rtl/matrix7_mm.v" "$ghrd/custom_ip/matrix/rtl/"
cp "$project/ip/matrix7_mm_hw.tcl" "$ghrd/custom_ip/matrix/ip/"
cd "$ghrd"
qsys-script --quartus-project=golden_top --search-path="$ghrd/custom_ip/**/*,$" --script="$project/scripts/integrate.tcl"
qsys-generate peripheral_subsys/peripheral_subsys.qsys --quartus-project=golden_top --synthesis=VERILOG --parallel=2 --search-path="$ghrd/custom_ip/**/*,$"
qsys-generate qsys_top.qsys --quartus-project=golden_top --synthesis=VERILOG --parallel=2 --search-path="$ghrd/custom_ip/**/*,$"
quartus_sh --flow compile golden_top
quartus_pfg -c output_files/golden_top.sof output_files/golden_top_hps.sof -o hps_path=software/u-boot/spl/u-boot-spl-dtb.hex
