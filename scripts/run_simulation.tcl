# Usage: tclsh scripts/run_simulation.tcl
set root_dir [file normalize [file join [file dirname [info script]] ".."]]
cd $root_dir
set temp_dir [expr {[info exists ::env(TEMP)] ? $::env(TEMP) : ([info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp")}]
set build_dir [file join $temp_dir qvision_sim]
file mkdir $build_dir
puts "Compiling QVision RTL & Testbench with Icarus Verilog..."
set iverilog_cmd [list iverilog -g2012 -DSIMULATION -I./rtl -o [file join $build_dir qvision_tb.out] \
    rtl/qvision_config.vh \
    rtl/reset_sync.v \
    rtl/pix_clk_gen.v \
    rtl/uart_rx.v \
    rtl/qr_buf.v \
    rtl/qr_encoder.v \
    rtl/qr_rs_encoder.v \
    rtl/qr_format_bch.v \
    rtl/qr_matrix_builder.v \
    rtl/qr_framebuffer.v \
    rtl/qr_pixel_mapper.v \
    rtl/vga_timing.v \
    rtl/rgb_dac_out.v \
    rtl/qvision_top.v \
    sim/tb_qr_pipeline.v]
if {[catch {exec {*}$iverilog_cmd} err]} {
    puts "Compilation Error:\n$err"
    exit 1
}
puts "Running Simulation..."
set vvp_cmd [list vvp [file join $build_dir qvision_tb.out]]
if {[catch {exec {*}$vvp_cmd} sim_output]} {
    puts "Simulation Output:\n$sim_output"
} else {
    puts "Simulation Output:\n$sim_output"
    puts "\n===> SIMULATION COMPLETED SUCCESSFULLY <==="
}
