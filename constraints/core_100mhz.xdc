# Internal-IP timing contract for the 100 MHz core integration experiment.
# Host signals are synchronous to core_clk. These budgets are assumptions
# for embedding the core, not measured board/CPU interface delays.
create_clock -name core_clk -period 10.000 [get_ports clk]
set_clock_uncertainty 0.100 [get_clocks core_clk]
set data_inputs [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_input_delay -clock core_clk -max 2.000 $data_inputs
set_input_delay -clock core_clk -min 0.500 $data_inputs
set_output_delay -clock core_clk -max 2.000 [all_outputs]
set_output_delay -clock core_clk -min 0.500 [all_outputs]
