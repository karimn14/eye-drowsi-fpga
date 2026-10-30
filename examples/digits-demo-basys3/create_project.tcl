# Vivado: Tools > Run Tcl Script  (or: vivado -mode batch -source create_project.tcl)
set proj_dir [file normalize [file dirname [info script]]]
create_project cnn_basys3 $proj_dir/vivado -part xc7a35tcpg236-1 -force
add_files [glob $proj_dir/rtl/*.v]
add_files $proj_dir/rtl/cnn_params.vh
set_property file_type {Verilog Header} [get_files cnn_params.vh]
set_property include_dirs [list $proj_dir/rtl] [get_filesets sources_1]
add_files -fileset constrs_1 $proj_dir/constraints/basys3_cnn.xdc
add_files -fileset sim_1 [list $proj_dir/sim/golden_rom.v $proj_dir/sim/tb_cnn_core.v $proj_dir/sim/tb_cnn_top.v]
set_property include_dirs [list $proj_dir/rtl] [get_filesets sim_1]
set_property top cnn_top [current_fileset]
set_property top tb_cnn_core [get_filesets sim_1]
update_compile_order -fileset sources_1
