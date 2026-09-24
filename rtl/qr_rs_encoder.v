`timescale 1ns/1ps
`include "qvision_config.vh"
module qr_rs_encoder (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire [6:0] cfg_d1,          // data codewords in a short block
    input  wire [6:0] cfg_d2,          // data codewords in a long block
    input  wire [6:0] cfg_n1,          // number of short blocks
    input  wire [6:0] cfg_n2,          // number of long blocks
    input  wire [4:0] cfg_parity,      // ECC codewords per block (uniform)
    input  wire [7:0] data_in,
    input  wire       data_valid,
    output reg  [7:0] cw_out,
    output reg        cw_valid,
    output reg        done
);
`include "qr_rs_gen_rom.vh"

    localparam [2:0] S_COLLECT   = 3'd0,
                     S_PROC      = 3'd1,   // LFSR over one block
                     S_PROC_WARM = 3'd6,   // fetch pipeline warm-up (1 cycle)
                     S_POUT      = 3'd2,   // store one block's parity
                     S_EMIT_D    = 3'd3,   // interleaved data out
                     S_EMIT_P    = 3'd4,   // interleaved parity out
                     S_DONE      = 3'd5,
                     S_DRAIN     = 3'd7;   // drain synchronous RAM output

    reg [2:0]  state;
    reg [6:0]  r_d1, r_d2, r_n1, r_n2;
    reg [4:0]  r_parity;
    reg [11:0] total_data_q;   // registered before the write-enable compare
    reg [11:0] collect_idx;
    reg [6:0]  block_idx;     // block being processed
    reg [6:0]  proc_idx;
    reg [11:0] proc_base;     // data_ram address of the block start
    reg [11:0] proc_base_r;
    reg [4:0]  pout_idx;
    reg [6:0]  em_elem;       // emit walk: element within the current round
    reg [6:0]  em_blk;        // emit walk: current block
    reg [11:0] em_base;       // emit walk: data_ram base of the current block
    wire [7:0] data_rdata, parity_rdata;
    reg        emit_valid_q, emit_parity_q;
    reg [7:0] synd     [0:`RS_MAX_PARITY-1];
    reg [7:0] next_synd[0:`RS_MAX_PARITY-1];
    reg [7:0] coeff    [0:`RS_MAX_PARITY-1];
    reg [7:0] fb_q;
    reg       proc_phase;
    integer j, k;

    wire [7:0]  nb         = {1'b0, r_n1} + {1'b0, r_n2};
    wire [6:0]  d_max      = (r_d2 > r_d1) ? r_d2 : r_d1;
    wire [6:0]  blk_len    = (block_idx < r_n1) ? r_d1 : r_d2;
    wire [6:0]  blk_len_em = (em_blk < r_n1) ? r_d1 : r_d2;
    wire [11:0] total_data = r_d1 * r_n1 + r_d2 * r_n2;
    wire [11:0] pout_addr = {5'b0, block_idx} * r_parity + {7'b0, pout_idx};
    wire [11:0] data_raddr = (state == S_EMIT_D)
                           ? (em_base + {5'b0, em_elem})
                           : (state == S_PROC)
                           ? (proc_base_r + {5'b0, proc_idx} + 12'd1)
                           : proc_base_r;
    wire [11:0] parity_raddr = {5'b0, em_blk} * r_parity
                             + {5'b0, em_elem};

    wire data_we = (state == S_COLLECT) && data_valid && !start &&
                   (collect_idx < total_data_q);
    wire parity_we = (state == S_POUT);
    wire [7:0] parity_wdata = synd[r_parity - 5'd1 - pout_idx];
    qvision_ram_8x3706_dp data_ram_u (
        .clk_a(clk), .we_a(data_we), .addr_a(collect_idx), .din_a(data_in), .dout_a(),
        .clk_b(clk), .we_b(1'b0), .addr_b(data_raddr), .din_b(8'h00), .dout_b(data_rdata)
    );
    qvision_ram_8x3706_dp parity_ram_u (
        .clk_a(clk), .we_a(parity_we), .addr_a(pout_addr), .din_a(parity_wdata), .dout_a(),
        .clk_b(clk), .we_b(1'b0), .addr_b(parity_raddr), .din_b(8'h00), .dout_b(parity_rdata)
    );

    always @(posedge clk) begin
        if (rst) total_data_q <= 12'd0;
        else     total_data_q <= total_data;
    end
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

    always @(*) begin
        next_synd[0] = gf_mul(coeff[0], fb_q);
        for (k = 1; k < `RS_MAX_PARITY; k = k + 1)
            next_synd[k] = (k < r_parity)
                           ? (synd[k-1] ^ gf_mul(coeff[k], fb_q))
                           : 8'h00;
    end

    always @(posedge clk) begin
        if (rst) begin
            state       <= S_COLLECT;
            cw_valid    <= 1'b0;
            done        <= 1'b0;
            cw_out      <= 8'd0;
            collect_idx <= 12'd0;
            block_idx   <= 7'd0;
            proc_idx    <= 7'd0;
            proc_base   <= 12'd0;
            proc_base_r <= 12'd0;
            pout_idx    <= 5'd0;
            em_elem     <= 7'd0;
            em_blk      <= 7'd0;
            em_base     <= 12'd0;
            emit_valid_q  <= 1'b0;
            emit_parity_q <= 1'b0;
            fb_q           <= 8'd0;
            proc_phase     <= 1'b0;
        end else begin
            cw_valid <= emit_valid_q;
            if (emit_valid_q)
                cw_out <= emit_parity_q ? parity_rdata : data_rdata;
            emit_valid_q <= 1'b0;
            done     <= 1'b0;

            case (state)
                S_COLLECT: begin
                    if (start) begin
                        r_d1      <= cfg_d1;
                        r_d2      <= cfg_d2;
                        r_n1      <= cfg_n1;
                        r_n2      <= cfg_n2;
                        r_parity  <= cfg_parity;
                        collect_idx <= 12'd0;
                        block_idx   <= 7'd0;
                        em_elem     <= 7'd0;
                        em_blk      <= 7'd0;
                        em_base     <= 12'd0;
                    end
                    if (data_valid && !start && collect_idx < total_data_q) begin
                        collect_idx <= collect_idx + 12'd1;
                        if (collect_idx + 12'd1 == total_data_q) begin
                            block_idx   <= 7'd0;
                            proc_idx    <= 7'd0;
                            proc_base   <= 12'd0;
                            proc_base_r <= 12'd0;
                            for (j = 0; j < `RS_MAX_PARITY; j = j + 1)
                                synd[j] <= 8'h00;
                            state <= S_PROC_WARM;
                        end
                    end
                end

                S_PROC_WARM: begin
                    proc_idx    <= 7'd0;
                    proc_phase  <= 1'b0;
                    for (j = 0; j < `RS_MAX_PARITY; j = j + 1)
                        coeff[j] <= gen_coeff(r_parity, j[4:0]);
                    state       <= S_PROC;
                end

                S_PROC: begin
                    if (!proc_phase) begin
                        fb_q       <= data_rdata ^ synd[r_parity - 5'd1];
                        proc_phase <= 1'b1;
                    end else begin
                        synd[0] <= next_synd[0];
                        for (k = 1; k < `RS_MAX_PARITY; k = k + 1)
                            if (k < r_parity) synd[k] <= next_synd[k];
                        proc_phase <= 1'b0;
                        if (proc_idx == blk_len - 7'd1) begin
                            pout_idx <= 5'd0;
                            state    <= S_POUT;
                        end else begin
                            proc_idx <= proc_idx + 7'd1;
                        end
                    end
                end

                S_POUT: begin
                    if (pout_idx == r_parity - 5'd1) begin
                        pout_idx <= 5'd0;
                        for (j = 0; j < `RS_MAX_PARITY; j = j + 1)
                            synd[j] <= 8'h00;
                        if (block_idx == nb - 8'd1) begin
                            em_elem     <= 7'd0;
                            em_blk      <= 7'd0;
                            em_base     <= 12'd0;
                            proc_base_r <= 12'd0;
                            state       <= S_EMIT_D;
                        end else begin
                            block_idx   <= block_idx + 7'd1;
                            proc_idx    <= 7'd0;
                            proc_base_r <= proc_base + {5'b0, blk_len};
                            proc_base   <= proc_base + {5'b0, blk_len};
                            state       <= S_PROC_WARM;
                        end
                    end else begin
                        pout_idx <= pout_idx + 5'd1;
                    end
                end

                S_EMIT_D: begin
                    if (em_elem < blk_len_em) begin
                        emit_valid_q  <= 1'b1;
                        emit_parity_q <= 1'b0;
                    end
                    if (em_blk == nb - 8'd1) begin
                        em_blk  <= 7'd0;
                        em_base <= 12'd0;
                        if (em_elem == d_max - 7'd1) begin
                            em_elem <= 7'd0;
                            state   <= S_EMIT_P;
                        end else begin
                            em_elem <= em_elem + 7'd1;
                        end
                    end else begin
                        em_blk  <= em_blk + 7'd1;
                        em_base <= em_base + {5'b0, blk_len_em};
                    end
                end

                S_EMIT_P: begin
                    emit_valid_q  <= 1'b1;
                    emit_parity_q <= 1'b1;
                    if (em_blk == nb - 8'd1) begin
                        em_blk <= 7'd0;
                        if (em_elem == r_parity - 5'd1) begin
                            em_elem <= 7'd0;
                            state   <= S_DRAIN;
                        end else begin
                            em_elem <= em_elem + 7'd1;
                        end
                    end else begin
                        em_blk <= em_blk + 7'd1;
                    end
                end

                S_DRAIN: begin
                    state <= S_DONE;
                end

                S_DONE: begin
                    done  <= 1'b1;
                    state <= S_COLLECT;
                end

                default: state <= S_COLLECT;
            endcase
        end
    end
endmodule
