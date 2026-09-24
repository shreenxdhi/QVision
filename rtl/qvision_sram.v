`timescale 1ns/1ps
// Inferred memories for simulation and FPGA builds.
module qvision_ram_8x4096_dp(
    input wire clk_a, input wire we_a, input wire [11:0] addr_a,
    input wire [7:0] din_a, output wire [7:0] dout_a,
    input wire clk_b, input wire we_b, input wire [11:0] addr_b,
    input wire [7:0] din_b, output reg [7:0] dout_b
);
    (* ram_style = "block" *) reg [7:0] mem [0:4095];
    assign dout_a = 8'h00;
    always @(posedge clk_a)
        if (we_a) mem[addr_a] <= din_a;
    always @(posedge clk_b) begin
        if (we_b) mem[addr_b] <= din_b;
        dout_b <= mem[addr_b];
    end
endmodule

module qvision_ram_8x3706_dp(
    input wire clk_a, input wire we_a, input wire [11:0] addr_a,
    input wire [7:0] din_a, output wire [7:0] dout_a,
    input wire clk_b, input wire we_b, input wire [11:0] addr_b,
    input wire [7:0] din_b, output reg [7:0] dout_b
);
    (* ram_style = "block" *) reg [7:0] mem [0:3705];
    assign dout_a = 8'h00;
    always @(posedge clk_a)
        if (we_a && addr_a < 12'd3706) mem[addr_a] <= din_a;
    always @(posedge clk_b) begin
        if (we_b && addr_b < 12'd3706) mem[addr_b] <= din_b;
        dout_b <= (addr_b < 12'd3706) ? mem[addr_b] : 8'h00;
    end
endmodule

module qvision_ram_1x31329_dp(
    input wire clk_a, input wire we_a, input wire [14:0] addr_a,
    input wire din_a, output wire dout_a,
    input wire clk_b, input wire we_b, input wire [14:0] addr_b,
    input wire din_b, output reg dout_b
);
    (* ram_style = "block" *) reg mem [0:31328];
    assign dout_a = 1'b0;
    always @(posedge clk_a)
        if (we_a && addr_a < 15'd31329) mem[addr_a] <= din_a;
    always @(posedge clk_b) begin
        if (we_b && addr_b < 15'd31329) mem[addr_b] <= din_b;
        dout_b <= (addr_b < 15'd31329) ? mem[addr_b] : 1'b0;
    end
endmodule
