# Isolate the PS synapse memory from population-state mux optimization.
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build synapse_bram_synthesis]
file mkdir $out
read_verilog [file join $root rtl lif_synapse_router.v]
synth_design -top lif_synapse_router -part xc7z020clg400-1 -mode out_of_context -directive RuntimeOptimized
create_clock -name core_clk -period 10.000 [get_ports clk]
report_utilization -file [file join $out utilization.rpt]
report_timing_summary -file [file join $out timing_synth.rpt]
set brams [get_cells -hier -filter {REF_NAME =~ RAMB*}]
set report [open [file join $out bram_check.txt] w]
puts $report "Top: lif_synapse_router; 256x256 signed 4-bit synapses"
puts $report "Inferred block RAM primitives: [llength $brams]"
foreach cell $brams {puts $report "$cell [get_property REF_NAME $cell]"}
close $report
if {[llength $brams] == 0} {error "PS synapse table did not infer block RAM"}
write_checkpoint -force [file join $out router_synth.dcp]
puts "PASS: 256x256 synapse table mapped to [llength $brams] block RAM primitives"
