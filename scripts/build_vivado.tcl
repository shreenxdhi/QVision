set project_name "qvision_blackboard"
set project_dir  "./vivado_qvision"
set part_number "xc7z007sclg400-1"

close_project -quiet
create_project -force $project_name $project_dir -part $part_number
add_files -norecurse [glob ./rtl/*.v]
update_compile_order -fileset sources_1
add_files -fileset constrs_1 -norecurse ./xdc/blackboard_qvision.xdc
set_property top qvision_top [current_fileset]

set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]

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

puts "2. Running Implementation + Bitstream (impl_1)..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    puts "===> IMPLEMENTATION FAILED <==="
    puts "Check logs in $project_dir/$project_name.runs/impl_1/runme.log"
    exit 1
}

puts "3. Timing gate on the routed design..."
set signoff_dcp $project_dir/$project_name.runs/impl_1/qvision_top_postroute_physopt.dcp
if {![file exists $signoff_dcp]} {
    puts "===> FINAL POST-ROUTE CHECKPOINT MISSING: $signoff_dcp <==="
    close_project -quiet
    exit 1
}
open_checkpoint $signoff_dcp
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
puts "Signoff WNS = $wns ns   WHS = $whs ns"
if {$wns < 0 || $whs < 0} {
    puts "===> TIMING NOT MET (WNS=$wns WHS=$whs) <==="
    close_project -quiet
    exit 1
}

report_timing_summary -delay_type min_max -max_paths 20 -report_unconstrained \
    -file $project_dir/qvision_top_timing_signoff.rpt
report_utilization -file $project_dir/qvision_top_utilization_final.rpt
report_route_status -file $project_dir/qvision_top_route_status_final.rpt
report_drc -file $project_dir/qvision_top_drc_final.rpt
report_methodology -file $project_dir/qvision_top_methodology_final.rpt
report_cdc -details -file $project_dir/qvision_top_cdc_final.rpt
report_clock_utilization -file $project_dir/qvision_top_clock_utilization_final.rpt
report_power -file $project_dir/qvision_top_power_final.rpt
puts "  BITSTREAM BUILD COMPLETED SUCCESSFULLY - TIMING MET"
puts "Bitstream Output File:"
puts "[file normalize $project_dir/$project_name.runs/impl_1/qvision_top.bit]\n"
puts "Signoff timing report: [file normalize $project_dir/qvision_top_timing_signoff.rpt]"
close_project -quiet
