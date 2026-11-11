# Generate firmware first: python -m tools.run_rv32_check --scenario mnist --generate-only
# Run: vivado -mode batch -source tools/synth_rv32_z710.tcl
set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
set out [file join $root build rv32_z710_timing]
file mkdir $out
set_param general.maxThreads 2
foreach source {aer_event_fifo.v aer_rr_select.v aer_rr_arbiter.v lif_transition.v lif_population_stepper.v lif_synapse_router.v lif_snn_core.v lif_aer_snn_core.v rate_encoder_transition.v aer_rate_encoder.v lif_rate_aer_snn_core.v vendor/picorv32.v axi_lite_endpoint.v lif_host_registers.v lif_rv32_soc.v} {
    read_verilog [file join $root rtl $source]
}
read_verilog [file join $root tools fixtures lif_rv32_timing_harness.v]
read_xdc [file join $root constraints timing_harness_100mhz.xdc]
synth_design -top lif_rv32_timing_harness -part xc7z010clg400-1 -mode out_of_context -directive RuntimeOptimized
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
set check [open [file join $out applied_constraints.xdc] r]
set applied [read $check]
close $check
if {[regexp -line {^\s*set_(false_path|multicycle_path)} $applied]} {error "Timing exceptions are not permitted"}
set check [open [file join $out check_timing.rpt] r]
set coverage [read $check]
close $check
foreach category {no_clock unconstrained_internal_endpoints loops latch_loops} {
    if {![regexp "checking $category \\(0\\)" $coverage]} {error "Timing coverage failed: $category"}
}
set brams [get_cells -hier -filter {REF_NAME =~ RAMB*}]
set synapse_brams [get_cells -hier -filter {REF_NAME =~ RAMB* && NAME =~ *synapse_router*}]
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup]==0 || [llength $hold]==0} {error "Missing setup/hold timing paths"}
set wns [get_property SLACK $setup]
set whs [get_property SLACK $hold]
set result [open [file join $out timing_result.json] w]
puts $result "\{\"top\":\"lif_rv32_timing_harness\",\"core\":\"lif_rv32_soc\",\"board\":\"Zybo Z7-10\",\"part\":\"xc7z010clg400-1\",\"clock_period_ns\":10.0,\"neuron_states\":256,\"synapse_entries\":65536,\"block_ram_primitives\":[llength $brams],\"synapse_bram_primitives\":[llength $synapse_brams],\"routed_setup_slack_ns\":$wns,\"routed_hold_slack_ns\":$whs,\"out_of_context\":true\}"
close $result
if {[llength $synapse_brams]!=8} {error "Expected eight synapse BRAM primitives"}
if {$wns<0 || $whs<0} {error "Routed timing failed: setup=$wns ns hold=$whs ns"}
puts "PASS: RV32/AXI/SNN on Z7-10 part at 100 MHz: setup $wns ns, hold $whs ns, [llength $brams] BRAMs"
