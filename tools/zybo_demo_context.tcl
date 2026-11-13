# Asynchronous inputs terminate only at the first flip-flop of each synchronizer.
set button_stages [get_cells -hier -regexp {.*buttons/button_meta_reg\[[01]\]}]
if {[llength $button_stages]!=2} {error "Expected exactly two button CDC input stages"}
set_false_path -from [get_ports {btn[*]}] -to [get_pins -of_objects $button_stages -filter {REF_PIN_NAME == D}]
set lock_stage [get_cells -hier -filter {NAME == lock_meta_reg}]
if {[llength $lock_stage]!=1} {error "Missing MMCM lock synchronizer first stage"}
# LOCKED is an asynchronous status output, not a legal timing startpoint.
# The first-stage D has this sole source; its second stage remains timed.
set_false_path -to [get_pins lock_meta_reg/D]
# LEDs have no clocked receiver; UART is an asynchronous serial interface.
# Bound their clock-to-pin propagation instead of inventing external setup/hold.
set_max_delay -datapath_only 20.0 -from [all_registers] -to [get_ports {led[*] led6_r led6_g led6_b pmod_uart_tx}]
# Constant PHY reset has no launching register and no timing relationship.
