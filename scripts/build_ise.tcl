if {$argc < 5} {
    puts "Usage: xtclsh build_ise.tcl <part> <ucf> <top> <ise_version> <family>"
    puts "Example: xtclsh build_ise.tcl xc6slx16-3-csg324 spartan6_generic.ucf qvision_top 14.7 spartan6"
    exit 1
}
set part [lindex $argv 0]
set ucf_file [lindex $argv 1] 
set top_module [lindex $argv 2]
set ise_version [lindex $argv 3]
set family [lindex $argv 4]
puts "QVision ISE Build Script"
puts "Part: $part"
puts "UCF: $ucf_file"
puts "Top: $top_module"
puts "ISE: $ise_version"
puts "Family: $family"
set project_name "qvision"
if {[file exists "$project_name.xise"]} {
    puts "Removing existing project..."
    file delete -force "$project_name.xise"
    file delete -force "$project_name.gise"
}
puts "Creating ISE project..."
project new "$project_name.xise"
project set family $family
project set device [lindex [split $part -] 0]
project set package [lindex [split $part -] 2]
project set speed [lindex [split $part -] 1]
project set top_level_module_type "HDL"
project set synthesis_tool "XST (VHDL/Verilog)"
project set simulator "ISim (VHDL/Verilog)"
project set "Verilog Include Directories" "../rtl"
project set "Verilog 2001" true
set script_dir [file dirname [file normalize [info script]]]
set rtl_dir [file join $script_dir "../rtl"]
set ucf_dir [file join $script_dir "../ucf"]
puts "Adding RTL source files..."
set rtl_files [glob -directory $rtl_dir *.v]
foreach file $rtl_files {
    puts "  Adding: $file"
    xfile add $file
}
if {[file exists "$rtl_dir/qvision_config.vh"]} {
    puts "  Adding: $rtl_dir/qvision_config.vh"  
    xfile add "$rtl_dir/qvision_config.vh"
}
if {[file exists "$ucf_dir/$ucf_file"]} {
    puts "Adding UCF constraints: $ucf_dir/$ucf_file"
    xfile add "$ucf_dir/$ucf_file"
} else {
    puts "ERROR: UCF file not found: $ucf_dir/$ucf_file"
    exit 1
}
puts "Setting top module: $top_module"
project set top $top_module
puts "Configuring synthesis settings..."
project set "Optimization Goal" "Speed"
project set "Optimization Effort" "Normal"
project set "Synthesis Constraints File" "$ucf_dir/$ucf_file"
project set "RAM Style" "Auto"
project set "ROM Style" "Auto"
project set "Place & Route Effort Level (Overall)" "High"
project save
puts "Starting synthesis..."
process run "Synthesize - XST"
if {[process get "Synthesize - XST" status] == "errors"} {
    puts "ERROR: Synthesis failed!"
    exit 1
}
puts "Synthesis completed successfully."
puts "Starting implementation..."
puts "Running Translate..."
process run "Translate"
if {[process get "Translate" status] == "errors"} {
    puts "ERROR: Translate failed!"
    exit 1
}
puts "Running Map..."
process run "Map"
if {[process get "Map" status] == "errors"} {
    puts "ERROR: Map failed!"
    exit 1
}
puts "Running Place & Route..."
process run "Place & Route"
if {[process get "Place & Route" status] == "errors"} {
    puts "ERROR: Place & Route failed!"
    exit 1
}
puts "Generating bitstream..."
process run "Generate Programming File"
if {[process get "Generate Programming File" status] == "errors"} {
    puts "ERROR: Bitstream generation failed!"
    exit 1
}
puts "Build completed successfully!"
puts "Bitstream: $project_name.bit"
puts "Generating reports..."
if {[file exists "$project_name.twr"]} {
    puts "Timing report generated: $project_name.twr"
}
if {[file exists "$project_name.par"]} {
    puts "Place & Route report generated: $project_name.par"  
}
project close
puts "Done."
