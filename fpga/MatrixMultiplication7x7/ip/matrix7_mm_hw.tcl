# Componente visível no catálogo do Platform Designer.
package require -exact qsys 25.1
set_module_property NAME matrix7_mm
set_module_property VERSION 1.0
set_module_property DISPLAY_NAME "MatrixMultiplication7x7 7x7"
set_module_property GROUP "Projetos DE25-Nano"
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE true
add_fileset synthesis_fileset QUARTUS_SYNTH
set_fileset_property synthesis_fileset TOP_LEVEL matrix7_mm
add_fileset_file ../rtl/matrix7_mm.v VERILOG PATH ../rtl/matrix7_mm.v TOP_LEVEL_FILE

add_interface clock clock end
add_interface_port clock clk clk Input 1
add_interface reset reset end
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT
add_interface_port reset reset reset Input 1

add_interface s0 avalon end
set_interface_property s0 associatedClock clock
set_interface_property s0 associatedReset reset
set_interface_property s0 addressUnits WORDS
set_interface_property s0 bitsPerSymbol 8
set_interface_property s0 readLatency 0
set_interface_property s0 readWaitTime 0
set_interface_property s0 writeWaitTime 0
set_interface_property s0 maximumPendingReadTransactions 0
add_interface_port s0 address address Input 9
add_interface_port s0 write write Input 1
add_interface_port s0 writedata writedata Input 32
add_interface_port s0 readdata readdata Output 32
