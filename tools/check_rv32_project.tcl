# Validates the generated project without modifying the user's open GUI project.
set ::env(SNN_SCENARIO) stress
source [file join [file dirname [info script]] create_rv32_project.tcl]
if {[get_property PART [current_project]] ne "xc7z010clg400-1"} {error "Wrong board part"}
if {[get_property top [get_filesets sources_1]] ne "lif_rv32_soc"} {error "Wrong synthesis top"}
if {[get_property top [get_filesets sim_1]] ne "lif_rv32_soc_tb"} {error "Wrong simulation top"}
if {![string match "*rv32_mnist/firmware.hex" [get_property generic [get_filesets sources_1]]]} {error "Wrong synthesis boot image"}
foreach source [get_files -all] {
    if {![file exists $source]} {error "Missing source $source"}
}
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
puts "PASS: Z7-10 generated project, canonical sources, learned synthesis boot image and RV32 GUI simulation"
