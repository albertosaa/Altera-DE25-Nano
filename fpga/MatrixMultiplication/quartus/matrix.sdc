# Mesmo clock de periféricos de 100 MHz utilizado pelo GHRD.
create_clock -name clk -period 10.000 [get_ports clk]
