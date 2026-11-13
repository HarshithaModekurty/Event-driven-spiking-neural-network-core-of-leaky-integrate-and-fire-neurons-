# Run from Vivado 2023.2: source tools/build_zybo_demo.tcl
# Optional environment: SNN_SCENARIO=stress, SNN_ILA=0 (default enabled).
set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
set scenario mnist
if {[info exists ::env(SNN_SCENARIO)]} {set scenario $::env(SNN_SCENARIO)}
if {$scenario ni {mnist stress}} {error "SNN_SCENARIO must be mnist or stress"}
set ila_enabled 1
if {[info exists ::env(SNN_ILA)]} {set ila_enabled $::env(SNN_ILA)}
set data [file join $root build board_demo $scenario]
if {![file exists [file join $data firmware.hex]]} {error "First run python -m tools.board_demo prepare --scenario $scenario"}
set config [open [file join $data sample_count.txt] r]
set samples [string trim [read $config]]
close $config
set out [file join $root build zybo_demo $scenario]
file mkdir $out
set mode [open [file join $out ila_mode.txt] w]
puts $mode $ila_enabled
close $mode
set host_python [lindex [auto_execok python] 0]
if {[info exists ::env(SNN_PYTHON)]} {set host_python $::env(SNN_PYTHON)}
# Vivado sets Python environment variables for its bundled interpreter.
# -E isolates the chosen host interpreter from those injected variables.
set resume_synth [expr {[info exists ::env(SNN_RESUME_SYNTH)] && $::env(SNN_RESUME_SYNTH) eq "1"}]
if {$resume_synth && [catch {exec $host_python -E -m tools.board_build_manifest check-synth --scenario $scenario --out $out} reason]} {
    puts "Synthesis inputs changed; rebuilding rather than reusing the checkpoint: $reason"
    set resume_synth 0
}
exec $host_python -E -m tools.board_build_manifest start --scenario $scenario --out $out
create_project zybo_demo [file join $out project_[clock seconds]] -part xc7z010clg400-1
set_param general.maxThreads 2
foreach source {aer_event_fifo.v aer_rr_select.v aer_rr_arbiter.v lif_transition.v lif_population_stepper.v lif_synapse_router.v lif_snn_core.v lif_aer_snn_core.v rate_encoder_transition.v aer_rate_encoder.v lif_rate_aer_snn_core.v vendor/picorv32.v axi_lite_endpoint.v lif_host_registers.v lif_rv32_soc.v board/uart_tx.v board/demo_buttons.v board/zybo_z710_clock.v board/snn_demo_reporter.v board/zybo_z710_top.v} {
    add_files [file join $root rtl $source]
}
add_files -fileset constrs_1 [file join $root constraints zybo_z710_demo.xdc]
set_property top zybo_z710_top [get_filesets sources_1]
set_property generic [list "BOOT_FILE=[file join $data firmware.hex]" "SAMPLES=$samples" "ENABLE_ILA=$ila_enabled"] [get_filesets sources_1]
if {$ila_enabled} {
    create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name snn_demo_ila
    set settings [list CONFIG.C_NUM_OF_PROBES 9 CONFIG.C_DATA_DEPTH 1024 CONFIG.C_INPUT_PIPE_STAGES 1 CONFIG.C_ADV_TRIGGER false CONFIG.C_EN_STRG_QUAL false CONFIG.C_TRIGIN_EN false CONFIG.C_TRIGOUT_EN false]
    set probe 0
    foreach width {1 1 8 4 160 1 1 1 1} {
        lappend settings CONFIG.C_PROBE${probe}_WIDTH $width
        # 0 = DATA_AND_TRIGGER; 1 = DATA. Only result-ready is a trigger.
        lappend settings CONFIG.C_PROBE${probe}_TYPE [expr {$probe==0 ? 0 : 1}]
        incr probe
    }
    set_property -dict $settings [get_ips snn_demo_ila]
    generate_target all [get_ips snn_demo_ila]
    synth_ip [get_ips snn_demo_ila]
}
update_compile_order -fileset sources_1
if {$resume_synth} {
    open_checkpoint [file join $out synthesized.dcp]
} else {
    synth_design -top zybo_z710_top -part xc7z010clg400-1 -directive RuntimeOptimized
    write_checkpoint -force [file join $out synthesized.dcp]
}
source [file join $root tools zybo_demo_context.tcl]
# opt_design implements the HDL-instantiated ILA and inserts its debug hub.
# implement_debug_core is unnecessary here and expects saved project constraints.
opt_design
place_design -directive Explore
phys_opt_design
route_design -directive Explore
write_checkpoint -force [file join $out routed.dcp]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out timing.rpt]
report_utilization -file [file join $out utilization.rpt]
report_utilization -hierarchical -file [file join $out hierarchy.rpt]
report_drc -file [file join $out drc.rpt]
report_cdc -file [file join $out cdc.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
report_exceptions -file [file join $out exceptions.rpt]
write_xdc -force [file join $out applied_constraints.xdc]
set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
if {$setup<0 || $hold<0} {error "Board timing failed: setup=$setup hold=$hold"}
set check [open [file join $out check_timing.rpt] r]
set coverage [read $check]
close $check
foreach category {no_clock unconstrained_internal_endpoints loops latch_loops} {
    if {![regexp "checking $category \\(0\\)" $coverage]} {error "Board timing coverage failed: $category"}
}
if {$ila_enabled} {write_debug_probes -force [file join $out zybo_demo.ltx]}
write_bitstream -force [file join $out zybo_demo.bit]
exec $host_python -E -m tools.board_build_manifest finish --scenario $scenario --out $out
set result [open [file join $out result.json] w]
puts $result "\{\"board\":\"Zybo Z7-10\",\"part\":\"xc7z010clg400-1\",\"scenario\":\"$scenario\",\"samples\":$samples,\"ila\":$ila_enabled,\"setup_slack_ns\":$setup,\"hold_slack_ns\":$hold,\"neuron_states\":256,\"physical_board_tested\":false\}"
close $result
puts "PASS: board bitstream $out/zybo_demo.bit; setup=$setup ns hold=$hold ns"
