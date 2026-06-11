`include "qvision_config.vh"
module pix_clk_gen (
    input  wire clk_in,
    output wire pix_clk,
    output wire locked
);
    wire clkfb;
    wire pll_out;

`ifdef BOARD_FAMILY_S6
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
`else
    // Spartan-3 variant (50 MHz to 25 MHz using DCM)
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
`endif

    BUFG pix_bufg (
        .I (pll_out),
        .O (pix_clk)
    );
endmodule
