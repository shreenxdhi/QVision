# XDC Constraints
# Clock Constraint: 100 MHz System Clock (Pin H16)
set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports { clk_in }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk_in }];
# Control Inputs (Active-low Reset SW0 and Push Buttons BTN0, BTN1)
set_property -dict { PACKAGE_PIN N15 IOSTANDARD LVCMOS33 } [get_ports { rst_n }];        # SW0 (Active Low Reset)
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports { btn_commit }];   # BTN0 (Commit Buffer)
set_property -dict { PACKAGE_PIN P16 IOSTANDARD LVCMOS33 } [get_ports { btn_clear }];    # BTN1 (Clear Buffer)
# UART RX Input (115200 Baud)
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports { uart_rx }];      # PMODA Pin 1 / UART RX
# Status LEDs (LD0 - LD3)
set_property -dict { PACKAGE_PIN N18 IOSTANDARD LVCMOS33 } [get_ports { led[0] }];       # LD0: Encoding Done
set_property -dict { PACKAGE_PIN M18 IOSTANDARD LVCMOS33 } [get_ports { led[1] }];       # LD1: UART Activity
set_property -dict { PACKAGE_PIN M17 IOSTANDARD LVCMOS33 } [get_ports { led[2] }];       # LD2: Buffer Committed
set_property -dict { PACKAGE_PIN L17 IOSTANDARD LVCMOS33 } [get_ports { led[3] }];       # LD3: Buffer Overflow / Error
set_property -dict { PACKAGE_PIN Y19 IOSTANDARD LVCMOS33 } [get_ports { vga_hs }];
set_property -dict { PACKAGE_PIN Y18 IOSTANDARD LVCMOS33 } [get_ports { vga_vs }];
set_property -dict { PACKAGE_PIN V20 IOSTANDARD LVCMOS33 } [get_ports { vga_r[0] }];
set_property -dict { PACKAGE_PIN U20 IOSTANDARD LVCMOS33 } [get_ports { vga_r[1] }];
set_property -dict { PACKAGE_PIN T20 IOSTANDARD LVCMOS33 } [get_ports { vga_r[2] }];
set_property -dict { PACKAGE_PIN P20 IOSTANDARD LVCMOS33 } [get_ports { vga_r[3] }];
set_property -dict { PACKAGE_PIN N20 IOSTANDARD LVCMOS33 } [get_ports { vga_g[0] }];
set_property -dict { PACKAGE_PIN M20 IOSTANDARD LVCMOS33 } [get_ports { vga_g[1] }];
set_property -dict { PACKAGE_PIN K19 IOSTANDARD LVCMOS33 } [get_ports { vga_g[2] }];
set_property -dict { PACKAGE_PIN J19 IOSTANDARD LVCMOS33 } [get_ports { vga_g[3] }];
set_property -dict { PACKAGE_PIN G19 IOSTANDARD LVCMOS33 } [get_ports { vga_b[0] }];
set_property -dict { PACKAGE_PIN H20 IOSTANDARD LVCMOS33 } [get_ports { vga_b[1] }];
set_property -dict { PACKAGE_PIN J20 IOSTANDARD LVCMOS33 } [get_ports { vga_b[2] }];
set_property -dict { PACKAGE_PIN L19 IOSTANDARD LVCMOS33 } [get_ports { vga_b[3] }];
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design];
