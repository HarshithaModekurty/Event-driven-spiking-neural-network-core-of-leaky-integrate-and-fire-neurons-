# Reproducible project independent of saved legacy GUI simulation selections.
# Generate vectors first: python -m tools.run_rv32_check --scenario mnist --generate-only
# Run in Vivado Tcl console: source tools/create_rv32_project.tcl
set root [file normalize [file join [file dirname [info script]] ..]]
set scenario mnist
if {[info exists ::env(SNN_SCENARIO)]} {set scenario $::env(SNN_SCENARIO)}
if {$scenario ni {mnist stress}} {error "SNN_SCENARIO must be mnist or stress"}
set data_folder [expr {$scenario eq "mnist" ? "rv32_mnist" : "rv32_network"}]
if {![file exists [file join $root build $data_folder firmware.hex]]} {error "Generate the selected scenario first"}
create_project -force lif_rv32 [file join $root build rv32_vivado] -part xc7z010clg400-1
foreach source {aer_event_fifo.v aer_rr_select.v aer_rr_arbiter.v lif_transition.v lif_population_stepper.v lif_synapse_router.v lif_snn_core.v lif_aer_snn_core.v rate_encoder_transition.v aer_rate_encoder.v lif_rate_aer_snn_core.v vendor/picorv32.v axi_lite_endpoint.v lif_host_registers.v lif_axi_lite.v lif_rv32_soc.v} {
    add_files [file join $root rtl $source]
}
add_files -fileset constrs_1 [file join $root constraints core_100mhz.xdc]
add_files -fileset sim_1 [file join $root rtl tb lif_rv32_soc_tb.v]
set_property top lif_rv32_soc [get_filesets sources_1]
set_property generic [list "BOOT_FILE=[file join $root build rv32_mnist firmware.hex]"] [get_filesets sources_1]
source [file join $root build $data_folder configure_vivado.tcl]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Created Z7-10 RV32 project; simulation scenario=$scenario. Board pin/clock wrapper is still required for a board bitstream."
