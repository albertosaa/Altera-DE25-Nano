.PHONY: sim
sim:
	mkdir -p build
	iverilog -g2012 -Wall -s tb_matrix_mm -o build/tb_matrix_mm rtl/matrix_mm.v sim/tb_matrix_mm.sv
	vvp build/tb_matrix_mm
