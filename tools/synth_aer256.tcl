# Historical xc7z020 context. Current Z7-10 integration uses synth_rv32_z710.tcl.
# Constrain before synthesis; implement the full 256-state core out of context.
# Run: vivado -mode batch -source tools/synth_aer256.tcl
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build aer256_timing]
file mkdir $out
set_param general.maxThreads 2
foreach source {aer_event_fifo.v aer_rr_select.v aer_rr_arbiter.v lif_transition.v lif_population_stepper.v lif_synapse_router.v lif_snn_core.v lif_aer_snn_core.v} {
    read_verilog [file join $root rtl $source]
}
read_verilog [file join $root tools fixtures lif_aer_timing_harness.v]
# XDC is passed to the synthesis engine, not applied only after optimization.
read_xdc [file join $root constraints timing_harness_100mhz.xdc]
synth_design -top lif_aer_timing_harness -part xc7z020clg400-1 -mode out_of_context -directive RuntimeOptimized
read_xdc [file join $root constraints timing_harness_context.xdc]
report_utilization -file [file join $out utilization_synth.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out timing_synth.rpt]
write_checkpoint -force [file join $out core_synth.dcp]
opt_design
place_design -directive Explore
phys_opt_design
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out timing_placed.rpt]
write_checkpoint -force [file join $out core_placed.dcp]
route_design -directive Explore
write_checkpoint -force [file join $out core_routed.dcp]
report_route_status -file [file join $out route_status.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out timing_routed.rpt]
report_timing -delay_type max -max_paths 10 -file [file join $out setup_paths.rpt]
report_timing -delay_type min -max_paths 10 -file [file join $out hold_paths.rpt]
report_utilization -file [file join $out utilization_routed.rpt]
report_utilization -hierarchical -file [file join $out utilization_hierarchical.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
report_drc -file [file join $out drc.rpt]
write_xdc -force [file join $out applied_constraints.xdc]
set brams [get_cells -hier -filter {REF_NAME =~ RAMB*}]
set synapse_brams [get_cells -hier -filter {REF_NAME =~ RAMB* && NAME =~ *synapse_router*}]
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup] == 0 || [llength $hold] == 0} {error "Missing setup/hold timing paths"}
set wns [get_property SLACK $setup]
set whs [get_property SLACK $hold]
set result [open [file join $out timing_result.json] w]
puts $result "\{"
puts $result "  \"top\": \"lif_aer_timing_harness\","
puts $result "  \"core\": \"lif_aer_snn_core\","
puts $result "  \"launch_bits\": 125,"
puts $result "  \"capture_bits\": 306,"
puts $result "  \"part\": \"xc7z020clg400-1\","
puts $result "  \"clock_period_ns\": 10.0,"
puts $result "  \"neuron_states\": 256,"
puts $result "  \"synapse_entries\": 65536,"
puts $result "  \"block_ram_primitives\": [llength $brams],"
puts $result "  \"routed_setup_slack_ns\": $wns,"
puts $result "  \"routed_hold_slack_ns\": $whs,"
puts $result "  \"out_of_context\": true"
puts $result "\}"
close $result
if {[llength $synapse_brams] != 8} {error "Expected eight BRAM primitives for the 256x256 synapse table"}
if {$wns < 0 || $whs < 0} {error "Routed timing failed: setup=$wns ns hold=$whs ns"}
puts "PASS: routed AER256 core at 100 MHz: setup slack $wns ns, hold slack $whs ns, [llength $brams] BRAMs"
