# Usage vivado -mode batch -source scripts/build_vivado.tcl
set project_name "qvision_blackboard"
set project_dir "./vivado_qvision"
set part_number "xc7z007sclg400-1"
close_project -quiet
create_project -force $project_name $project_dir -part $part_number
add_files -norecurse [glob ./rtl/*.v]
update_compile_order -fileset sources_1
add_files -fileset constrs_1 -norecurse ./xdc/blackboard_qvision.xdc
set_property top qvision_top [current_fileset]
puts "Vivado Hardware Project Created for QVision QR Generator"
puts "Target Device : XC7007S ($part_number)"
puts "Top Module    : qvision_top"
puts "1. Running Synthesis (synth_1)..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "===> SYNTHESIS FAILED <==="
    puts "Check logs in $project_dir/$project_name.runs/synth_1/runme.log"
    exit 1
}
puts "2. Running Implementation (impl_1)..."
launch_runs impl_1 -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    puts "===> IMPLEMENTATION FAILED <==="
    puts "Check logs in $project_dir/$project_name.runs/impl_1/runme.log"
    exit 1
}
puts "3. Generating Bitstream..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "  BITSTREAM BUILD COMPLETED SUCCESSFULLY!"
puts "Bitstream Output File:"
puts "[file normalize $project_dir/$project_name.runs/impl_1/qvision_top.bit]\n"
