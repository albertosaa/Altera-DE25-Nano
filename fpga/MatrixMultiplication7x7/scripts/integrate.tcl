# Executar via qsys-script dentro da cópia de trabalho do GHRD.
# Os nomes abaixo foram conferidos no peripheral_subsys.qsys da demonstração.
package require -exact qsys 25.1
set system_file "[pwd]/peripheral_subsys/peripheral_subsys.qsys"
load_system $system_file
# Ao usar como base a cópia 2x2 já atualizada, remove somente o periférico antigo.
if {[lsearch -exact [get_instances] matrix_0] != -1} {
    remove_instance matrix_0
}
if {[lsearch -exact [get_instances] matrix7_0] != -1} {
    remove_instance matrix7_0
}
add_instance matrix7_0 matrix7_mm 1.0
add_connection periph_clk.out_clk matrix7_0.clock
add_connection periph_rst_in.out_reset matrix7_0.reset
add_connection pb_cpu_0.m0 matrix7_0.s0
set_connection_parameter_value pb_cpu_0.m0/matrix7_0.s0 baseAddress 0x00011000
save_system $system_file
