# Clocked launch/capture FFs provide the actual synchronous core context.
create_clock -name core_clk -period 10.000 [get_ports clk]
set_clock_uncertainty 0.100 [get_clocks core_clk]
# Only measurement outputs leave the fixture; production core ports are
# routed between placed registers. These output budgets are not board claims.
set_output_delay -clock core_clk -max 2.000 [all_outputs]
set_output_delay -clock core_clk -min 0.500 [all_outputs]
