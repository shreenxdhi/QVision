# QVision constraints for the RealDigital Blackboard (XC7Z007S).
# VGA uses an external resistor-DAC on Pmod A/B; UART RX uses Pmod C pin 1.
set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports { clk_in }]
create_clock -name sys_clk_pin -period 10.000 -waveform {0.000 5.000} [get_ports { clk_in }]

# Board inputs are asynchronous to sys_clk.
set_false_path -from [get_ports { rst_n }]
set_false_path -from [get_ports { btn_commit }]
set_false_path -from [get_ports { btn_clear }]
set_false_path -from [get_ports { uart_rx }]
set_false_path -to [get_ports { led[*] }]

# Reset and controls
set_property -dict { PACKAGE_PIN R17 IOSTANDARD LVCMOS33 } [get_ports { rst_n }];        # SW0 (Active Low Reset)
set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 } [get_ports { btn_commit }];   # BTN0 (Commit Buffer)
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports { btn_clear }];    # BTN1 (Clear Buffer)

# UART RX
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports { uart_rx }];      # Pmod C pin 1 / UART RX

# Status LEDs
set_property -dict { PACKAGE_PIN N20 IOSTANDARD LVCMOS33 } [get_ports { led[0] }];       # LD0: Encoding Done
set_property -dict { PACKAGE_PIN P20 IOSTANDARD LVCMOS33 } [get_ports { led[1] }];       # LD1: UART Activity
set_property -dict { PACKAGE_PIN R19 IOSTANDARD LVCMOS33 } [get_ports { led[2] }];       # LD2: Overflow / clamp
set_property -dict { PACKAGE_PIN T20 IOSTANDARD LVCMOS33 } [get_ports { led[3] }];       # LD3: UART framing error

# VGA output through an external resistor-DAC.
set_property -dict { PACKAGE_PIN F16 IOSTANDARD LVCMOS33 } [get_ports { vga_hs }];   # Pmod A pin 1
set_property -dict { PACKAGE_PIN F17 IOSTANDARD LVCMOS33 } [get_ports { vga_vs }];   # Pmod A pin 2
set_property -dict { PACKAGE_PIN G19 IOSTANDARD LVCMOS33 } [get_ports { vga_r[0] }]; # Pmod A pin 3
set_property -dict { PACKAGE_PIN G20 IOSTANDARD LVCMOS33 } [get_ports { vga_r[1] }]; # Pmod A pin 4
set_property -dict { PACKAGE_PIN E18 IOSTANDARD LVCMOS33 } [get_ports { vga_r[2] }]; # Pmod A pin 7
set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports { vga_r[3] }]; # Pmod A pin 8
set_property -dict { PACKAGE_PIN E17 IOSTANDARD LVCMOS33 } [get_ports { vga_g[0] }]; # Pmod A pin 9
set_property -dict { PACKAGE_PIN D18 IOSTANDARD LVCMOS33 } [get_ports { vga_g[1] }]; # Pmod A pin 10
set_property -dict { PACKAGE_PIN D19 IOSTANDARD LVCMOS33 } [get_ports { vga_g[2] }]; # Pmod B pin 1
set_property -dict { PACKAGE_PIN D20 IOSTANDARD LVCMOS33 } [get_ports { vga_g[3] }]; # Pmod B pin 2
set_property -dict { PACKAGE_PIN F19 IOSTANDARD LVCMOS33 } [get_ports { vga_b[0] }]; # Pmod B pin 3
set_property -dict { PACKAGE_PIN F20 IOSTANDARD LVCMOS33 } [get_ports { vga_b[1] }]; # Pmod B pin 4
set_property -dict { PACKAGE_PIN C20 IOSTANDARD LVCMOS33 } [get_ports { vga_b[2] }]; # Pmod B pin 7
set_property -dict { PACKAGE_PIN B20 IOSTANDARD LVCMOS33 } [get_ports { vga_b[3] }]; # Pmod B pin 8

# Bitstream options
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
