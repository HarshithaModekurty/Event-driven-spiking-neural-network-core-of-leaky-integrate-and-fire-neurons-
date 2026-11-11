# Validate the saved project and generated GUI settings without modifying it.
# First run: python -m tools.run_rate_snn_check --generate-only
# Then: vivado -mode batch -source tools/check_rate_project.tcl
set root [file normalize [file join [file dirname [info script]] ..]]
open_project -read_only [file join $root RTL_PROJECT.xpr]
foreach source [get_files -all] {
    if {![file exists $source]} {error "Missing project source: $source"}
}
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
if {[get_property top [get_filesets sources_1]] ni {lif_rate_aer_snn_core lif_rv32_soc}} {error "Unexpected synthesis top"}
if {[get_property top [get_filesets sim_1]] ni {lif_rate_snn_tb lif_rv32_soc_tb lif_mnist_tb lif_aer_snn_core_tb}} {error "Unexpected simulation top"}
# Copy path strings before closing: Vivado file objects belong to the old
# project and must not be passed into the newly created project.
set sources {}
foreach source [get_files -of_objects [get_filesets sources_1]] {
    lappend sources [file normalize [get_property NAME $source]]
}
close_project
create_project -force rate_gui_probe [file join $root build rate_gui_probe] -part xc7z020clg400-1
add_files $sources
add_files -fileset sim_1 [file join $root rtl tb lif_rate_snn_tb.v]
source [file join $root build rate_network configure_vivado.tcl]
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
puts "PASS: rate project sources, saved tops and generated GUI simulation settings"
