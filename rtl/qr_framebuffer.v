`timescale 1ns/1ps
`include "qvision_config.vh"
module qr_framebuffer #(
    parameter DEPTH = `FB_DEPTH          // 177*177 max (versions 1-40)
)(
    input  wire         clka,
    input  wire [`FB_ADDR_BITS-1:0] addra,
    input  wire         dina,
    input  wire         wea,
    input  wire         clkb,
    input  wire [`FB_ADDR_BITS-1:0] addrb,
    output wire         doutb
);
    // Simple dual-port SRAM: system-domain write, pixel-domain read.
    qvision_ram_1x31329_dp memory_u (
        .clk_a(clka), .we_a(wea), .addr_a(addra), .din_a(dina), .dout_a(),
        .clk_b(clkb), .we_b(1'b0), .addr_b(addrb), .din_b(1'b0), .dout_b(doutb)
    );
endmodule
