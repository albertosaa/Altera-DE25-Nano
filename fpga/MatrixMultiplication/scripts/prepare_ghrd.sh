#!/bin/sh
# Preserva a demonstração original: todas as alterações vão para build/ghrd.
set -eu
project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_ghrd=${1:-"$project/../../../ResourcePackage/Demonstration/SoC_FPGA/GHRD"}
destination=${2:-"$project/build/ghrd_final"}
if [ -e "$destination" ]; then
    echo "Já existe $destination. Use a cópia existente ou escolha um diretório novo." >&2
    exit 1
fi
test -f "$source_ghrd/golden_top.qpf"
mkdir -p "$project/build"
cp -R "$source_ghrd" "$destination"
mkdir -p "$destination/custom_ip/matrix/ip" "$destination/custom_ip/matrix/rtl"
cp "$project/ip/matrix_mm_hw.tcl" "$destination/custom_ip/matrix/ip/"
cp "$project/rtl/matrix_mm.v" "$destination/custom_ip/matrix/rtl/"
cd "$destination"
qsys-script --quartus-project=golden_top --search-path="$destination/custom_ip/**/*,$" --script="$project/scripts/integrate.tcl"
echo "Abra no Quartus: $destination/golden_top.qpf"
