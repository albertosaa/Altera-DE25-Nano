# Executar via qsys-script dentro da cópia de trabalho do GHRD.
# Os nomes abaixo foram conferidos no peripheral_subsys.qsys da demonstração.
package require -exact qsys 25.1
set system_file "[pwd]/peripheral_subsys/peripheral_subsys.qsys"
load_system $system_file
if {[lsearch -exact [get_instances] matrix_0] != -1} {
    remove_instance matrix_0
}
add_instance matrix_0 matrix_mm 1.0
add_connection periph_clk.out_clk matrix_0.clock
add_connection periph_rst_in.out_reset matrix_0.reset
add_connection pb_cpu_0.m0 matrix_0.s0
set_connection_parameter_value pb_cpu_0.m0/matrix_0.s0 baseAddress 0x00010100
save_system $system_file
