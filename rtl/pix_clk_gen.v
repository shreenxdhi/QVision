module pix_clk_gen (
    input  wire clk_in,
    output wire pix_clk,
    output wire locked
);
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
endmodule
