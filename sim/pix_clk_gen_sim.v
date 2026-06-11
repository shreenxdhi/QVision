// Behavioral stub for simulation that replaces the Xilinx PLL_BASE primitive
`timescale 1ns/1ps
module pix_clk_gen (
    input  wire clk_in,
    output wire pix_clk,
    output wire locked
);
    reg pix_clk_r = 1'b0;
    always @(posedge clk_in)
        pix_clk_r <= ~pix_clk_r;   // divide by 2: 50 MHz → 25 MHz
    assign pix_clk = pix_clk_r;
    assign locked  = 1'b1;          // always locked — no PLL startup delay
endmodule
