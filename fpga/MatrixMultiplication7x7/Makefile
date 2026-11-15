.PHONY: sim
sim:
	mkdir -p build
	iverilog -g2012 -Wall -s tb_matrix7_mm -o build/tb_matrix7_mm rtl/matrix7_mm.v sim/tb_matrix7_mm.sv
	vvp build/tb_matrix7_mm
