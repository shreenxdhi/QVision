`timescale 1ns/1ps
`include "qvision_config.vh"
// Pixel clock generation: 25.000 MHz for 640x480@60 Hz VGA.  The board
// family is selected by the ifdef chain in qvision_config.vh.
module pix_clk_gen (
    input  wire clk_in,
    output wire pix_clk,
    output wire locked
);
`ifdef SIMULATION
    // Behavioral divider for simulation (any input frequency / 2)
    reg [1:0] clk_cnt = 2'b00;
    always @(posedge clk_in) begin
        clk_cnt <= clk_cnt + 1'b1;
    end
    assign pix_clk = clk_cnt[1];
    assign locked  = 1'b1;

`elsif BOARD_FAMILY_ZYNQ
    // Xilinx 7-Series / Zynq MMCM: 100 MHz -> 25 MHz
    wire clkfb;
    wire pll_out;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(10.0),      // VCO = 1000 MHz
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(10.0),        // 100 MHz input
        .CLKOUT0_DIVIDE_F(40.0),     // 1000 / 40 = 25 MHz
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(0.0),
        .DIVCLK_DIVIDE(1),
        .REF_JITTER1(0.010)
    ) mmcm_inst (
        .CLKIN1   (clk_in),
        .CLKFBIN  (clkfb),
        .CLKFBOUT (clkfb),
        .CLKFBOUTB(),
        .CLKOUT0  (pll_out),
        .CLKOUT0B (),
        .CLKOUT1  (),
        .CLKOUT1B (),
        .CLKOUT2  (),
        .CLKOUT2B (),
        .CLKOUT3  (),
        .CLKOUT3B (),
        .CLKOUT4  (),
        .CLKOUT5  (),
        .CLKOUT6  (),
        .LOCKED   (locked),
        .PWRDWN   (1'b0),
        .RST      (1'b0)
    );

    BUFG pix_bufg (
        .I (pll_out),
        .O (pix_clk)
    );

`elsif BOARD_FAMILY_S6
    // Spartan-6 PLL: 50 MHz -> 25 MHz
    wire clkfb;
    wire pll_out;

    PLL_BASE #(
        .BANDWIDTH        ("OPTIMIZED"),
        .CLK_FEEDBACK     ("CLKFBOUT"),
        .CLKFBOUT_MULT    (10),
        .CLKFBOUT_PHASE   (0.0),
        .CLKIN_PERIOD     (20.0),
        .CLKOUT0_DIVIDE   (20),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE    (0.0),
        .DIVCLK_DIVIDE    (1),
        .REF_JITTER       (0.100)
    ) pll_inst (
        .CLKFBIN  (clkfb),
        .CLKFBOUT (clkfb),
        .CLKIN    (clk_in),
        .CLKOUT0  (pll_out),
        .LOCKED   (locked),
        .RST      (1'b0)
    );

    BUFG pix_bufg (
        .I (pll_out),
        .O (pix_clk)
    );

`else
    // Spartan-3 DCM: 50 MHz -> 25 MHz (CLKDV)
    wire clkfb;
    wire pll_out;

    DCM_SP #(
        .CLKDV_DIVIDE(2.0),
        .CLKIN_PERIOD(20.0),
        .CLK_FEEDBACK("1X")
    ) dcm_inst (
        .CLKIN(clk_in),
        .CLKFB(clkfb),
        .RST(1'b0),
        .PSEN(1'b0),
        .PSINCDEC(1'b0),
        .PSCLK(1'b0),
        .DSSEN(1'b0),
        .CLK0(clkfb),
        .CLK90(),
        .CLK180(),
        .CLK270(),
        .CLK2X(),
        .CLK2X180(),
        .CLKDV(pll_out),
        .CLKFX(),
        .CLKFX180(),
        .STATUS(),
        .LOCKED(locked),
        .PSDONE()
    );

    BUFG pix_bufg (
        .I (pll_out),
        .O (pix_clk)
    );
`endif
endmodule
