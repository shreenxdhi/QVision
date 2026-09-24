set root_dir [file normalize [file join [file dirname [info script]] ".."]]
cd $root_dir
set temp_dir [expr {[info exists ::env(TEMP)] ? $::env(TEMP) : ([info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp")}]
set build_dir [file join $temp_dir qvision_sim]
file mkdir $build_dir

set golden "1fc77f82120dd5576ea6bb75f5d82ca0ff55fc026017c17c09c97e78a64c10601e69400be5ff05960bf9375524ba8925d4a520886bfd694"

puts "Compiling QVision RTL & Testbench with Icarus Verilog..."
set iverilog_cmd [list iverilog -g2012 -DSIMULATION -I./rtl \
    -o [file join $build_dir qvision_tb.out] \
    rtl/qvision_sram.v \
    rtl/qvision_config.vh \
    rtl/reset_sync.v \
    rtl/pix_clk_gen.v \
    rtl/uart_rx.v \
    rtl/qr_buf.v \
    rtl/qr_controller.v \
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
set vvp_cmd [list vvp [file join $build_dir qvision_tb.out] \
    +PAYLOAD=48454c4c4f +PLEN=5 +GOLDEN=$golden]
if {[catch {exec {*}$vvp_cmd} sim_output]} {
    puts "Simulation Output:\n$sim_output"
    exit 1
}
puts "Simulation Output:\n$sim_output"
if {[string first "STATUS PASS" $sim_output] >= 0} {
    puts "\n===> SIMULATION PASSED: QR matrix matches the ISO 18004 golden reference <==="
} else {
    puts "\n===> SIMULATION FAILED <==="
    exit 1
}
