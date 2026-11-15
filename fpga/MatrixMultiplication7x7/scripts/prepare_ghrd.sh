#!/bin/sh
# Preserva o projeto de origem: todas as alterações vão para build/ghrd_7x7.
set -eu
project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_ghrd=${1:-"$project/../../../ResourcePackage/Demonstration/SoC_FPGA/GHRD"}
destination=${2:-"$project/build/ghrd_7x7"}
if [ -e "$destination" ]; then
    echo "Já existe $destination. Use a cópia existente ou escolha um diretório novo." >&2
    exit 1
fi
test -f "$source_ghrd/golden_top.qpf"
mkdir -p "$project/build"
cp -R "$source_ghrd" "$destination"
# Se a origem já estava compilada, separa seus bitstreams para não confundir
# o circuito 2x2/fábrica com o novo 7x7 antes da compilação completa.
mkdir -p "$destination/output_files/reference_bitstreams"
for name in golden_top.sof golden_top_hps.sof golden_top_hps.jic; do
    if [ -f "$destination/output_files/$name" ]; then
        mv "$destination/output_files/$name" "$destination/output_files/reference_bitstreams/"
    fi
done
mkdir -p "$destination/custom_ip/matrix/ip" "$destination/custom_ip/matrix/rtl"
cp "$project/ip/matrix7_mm_hw.tcl" "$destination/custom_ip/matrix/ip/"
cp "$project/rtl/matrix7_mm.v" "$destination/custom_ip/matrix/rtl/"
cd "$destination"
qsys-script --quartus-project=golden_top --search-path="$destination/custom_ip/**/*,$" --script="$project/scripts/integrate.tcl"
echo "Abra no Quartus: $destination/golden_top.qpf"
