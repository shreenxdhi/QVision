`timescale 1ns/1ps
module qr_rs_encoder #(
    parameter PARITY_BYTES = 10   
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,        
    input  wire [7:0] data_in,      
    input  wire       data_valid,
    output reg  [7:0] parity_out,   
    output reg        parity_valid, 
    output reg        done          
);
    function [7:0] gf_mul;
        input [7:0] a, b;
        integer i;
        reg [7:0] aa, bb, p;
        begin
            aa = a; bb = b; p = 8'd0;
            for (i = 0; i < 8; i = i + 1) begin
                if (bb[0]) p = p ^ aa;
                if (aa[7]) aa = (aa << 1) ^ 8'h1D;
                else        aa = (aa << 1);
                bb = bb >> 1;
            end
            gf_mul = p;
        end
    endfunction
    wire [7:0] gen [0:PARITY_BYTES];
    assign gen[0]=8'hC1; assign gen[1]=8'h9D; assign gen[2]=8'h71; assign gen[3]=8'h5F; assign gen[4]=8'h5E;
    assign gen[5]=8'hC7; assign gen[6]=8'h6F; assign gen[7]=8'h9F; assign gen[8]=8'hC2; assign gen[9]=8'hD8;
    assign gen[10]=8'h01;
    reg [7:0] synd      [0:PARITY_BYTES-1];
    reg [7:0] next_synd [0:PARITY_BYTES-1];
    reg [3:0] out_idx;
    reg [1:0] state;
    reg       seen_byte;
    reg [7:0] fb;
    integer   k;
    localparam S_IDLE = 2'd0,
               S_PROC = 2'd1,
               S_OUT  = 2'd2;
    always @(*) begin
        fb = data_in ^ synd[PARITY_BYTES-1];
        next_synd[0] = gf_mul(gen[0], fb);
        for (k = 1; k < PARITY_BYTES; k = k + 1)
            next_synd[k] = synd[k-1] ^ gf_mul(gen[k], fb);
    end
    always @(posedge clk) begin
        if (rst) begin
            state        <= S_IDLE;
            out_idx      <= 4'd0;
            parity_out   <= 8'd0;
            parity_valid <= 1'b0;
            done         <= 1'b0;
            seen_byte    <= 1'b0;
            synd[0] <= 8'd0; synd[1] <= 8'd0; synd[2] <= 8'd0; synd[3] <= 8'd0; synd[4] <= 8'd0;
            synd[5] <= 8'd0; synd[6] <= 8'd0; synd[7] <= 8'd0; synd[8] <= 8'd0; synd[9] <= 8'd0;
        end else begin
            parity_valid <= 1'b0;
            done         <= 1'b0;
            case (state)
                S_IDLE: begin
                    seen_byte <= 1'b0;
                    out_idx   <= 4'd0;
                    if (start) begin
                        synd[0] <= 8'd0; synd[1] <= 8'd0; synd[2] <= 8'd0; synd[3] <= 8'd0; synd[4] <= 8'd0;
                        synd[5] <= 8'd0; synd[6] <= 8'd0; synd[7] <= 8'd0; synd[8] <= 8'd0; synd[9] <= 8'd0;
                        state <= S_PROC;
                    end
                end
                S_PROC: begin
                    if (data_valid) begin
                        parity_out   <= data_in;
                        parity_valid <= 1'b1;
                        synd[0] <= next_synd[0]; synd[1] <= next_synd[1]; synd[2] <= next_synd[2];
                        synd[3] <= next_synd[3]; synd[4] <= next_synd[4]; synd[5] <= next_synd[5];
                        synd[6] <= next_synd[6]; synd[7] <= next_synd[7]; synd[8] <= next_synd[8];
                        synd[9] <= next_synd[9];
                        seen_byte <= 1'b1;
                    end else if (seen_byte) begin
                        out_idx <= 4'd0;
                        state   <= S_OUT;
                    end
                end
                S_OUT: begin
                    if (out_idx < PARITY_BYTES) begin
                        parity_out   <= synd[PARITY_BYTES - 1 - out_idx];
                        parity_valid <= 1'b1;
                        out_idx      <= out_idx + 1;
                    end else begin
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
