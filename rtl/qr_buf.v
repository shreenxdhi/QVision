`timescale 1ns/1ps
`include "qvision_config.vh"
module qr_buf #(
    parameter BUF_SIZE  = `BUF_SIZE,       // must be a power of two
    parameter ADDR_BITS = `BUF_ADDR_BITS
)(
    input  wire         clk,
    input  wire         rst,
    input  wire [7:0]   in_byte,
    input  wire         in_valid,
    input  wire         commit,
    input  wire         clear,
    input  wire         rd_clr,     // reset the read pointer only (re-read)
    output wire [7:0]   rd_data,
    input  wire         rd_en,
    output wire [`LEN_BITS-1:0] length,
    output reg          committed_flag,
    output reg          overflow_flag
);
    reg [ADDR_BITS:0]   wr_ptr;
    reg [ADDR_BITS:0]   rd_ptr;
    reg [ADDR_BITS:0]   committed_length;

    wire [ADDR_BITS-1:0] wr_addr = wr_ptr[ADDR_BITS-1:0];
    wire [ADDR_BITS-1:0] rd_addr = rd_ptr[ADDR_BITS-1:0];
    // registered SRAM read: prefetch the next address so rd_data always
    // corresponds to rd_ptr after the pointer advances
    wire [ADDR_BITS-1:0] rd_mem_addr = rd_en ? (rd_addr + {{(ADDR_BITS-1){1'b0}}, 1'b1})
                                             : rd_addr;
    wire [ADDR_BITS:0]   current_length;

    assign current_length = (wr_ptr >= rd_ptr) ? (wr_ptr - rd_ptr)
                                               : (BUF_SIZE - rd_ptr + wr_ptr);
    wire full = (wr_ptr[ADDR_BITS-1:0] == rd_ptr[ADDR_BITS-1:0]) &&
                (wr_ptr[ADDR_BITS] != rd_ptr[ADDR_BITS]);

    assign length  = committed_flag ? committed_length[`LEN_BITS-1:0]
                                    : current_length[`LEN_BITS-1:0];
    wire buffer_we = in_valid && !committed_flag && !clear && !full;
    wire [7:0] buffer_q;

    qvision_ram_8x4096_dp buffer_u (
        .clk_a(clk), .we_a(buffer_we), .addr_a(wr_addr), .din_a(in_byte), .dout_a(),
        .clk_b(clk), .we_b(1'b0), .addr_b(rd_mem_addr), .din_b(8'h00), .dout_b(buffer_q)
    );

    assign rd_data = buffer_q;

    always @(posedge clk) begin
        if (rst) begin
            wr_ptr           <= 0;
            rd_ptr           <= 0;
            committed_flag   <= 0;
            committed_length <= 0;
            overflow_flag    <= 0;
        end else begin
            if (clear) begin
                wr_ptr           <= 0;
                rd_ptr           <= 0;
                committed_flag   <= 0;
                committed_length <= 0;
                overflow_flag    <= 0;
            end
            else if (commit && !committed_flag) begin
                committed_flag   <= 1;
                committed_length <= wr_ptr[ADDR_BITS:0];
            end
            else if (in_valid && !committed_flag) begin
                if (!full)
                    wr_ptr <= wr_ptr + 1;
                else
                    overflow_flag <= 1;
            end

            if (rd_clr)
                rd_ptr <= 0;
            else if (rd_en && committed_flag && (rd_ptr != wr_ptr))
                rd_ptr <= rd_ptr + 1;
        end
    end
endmodule
