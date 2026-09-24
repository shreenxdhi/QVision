`timescale 1ns/1ps
`include "qvision_config.vh"
module qr_controller (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [`LEN_BITS-1:0] buf_length,
    input  wire [7:0]  buf_rd_data,
    output wire        buf_scan_en,     // read one byte per cycle (scan phase)
    output reg         buf_rd_clr,      // reset the buffer read pointer
    input  wire [1:0]  ec_level,
    output reg         pack_start,
    output reg  [1:0]  pack_mode,
    output reg  [`LEN_BITS-1:0] pack_len,
    output reg  [4:0]  pack_cnt_w,      // char-count field width (by version)
    output reg  [`LEN_BITS-1:0] pack_data_cw,
    output reg  [15:0] pack_payload_bits,
    output reg         rs_start,
    output reg  [6:0]  rs_d1,           // data cw per short block
    output reg  [6:0]  rs_d2,           // data cw per long block
    output reg  [6:0]  rs_n1,           // number of short blocks
    output reg  [6:0]  rs_n2,           // number of long blocks
    output reg  [4:0]  rs_parity,
    output reg         mb_start,
    output reg  [5:0]  mb_version,
    output reg  [7:0]  mb_size,
    output reg  [`LEN_BITS-1:0] mb_total_cw,
    output reg  [1:0]  mb_ec_fmt,       // ISO format-info EC bits
    input  wire        mb_done,
    output reg         too_long
);
`include "qr_tables.vh"
`undef QR_TABLES_VH
    localparam M_BYTE = 2'd0, M_NUM = 2'd1, M_ALNUM = 2'd2, M_KANJI = 2'd3;

    localparam [2:0] S_IDLE    = 3'd0,
                     S_SCAN    = 3'd1,
                     S_SELECT  = 3'd2,   // iterative version fit (0+ cycles)
                     S_CFG     = 3'd3,   // latch block table for chosen version
                     S_LAUNCH  = 3'd4,   // configure + start the pipeline
                     S_RUN     = 3'd5;

    reg [2:0] state;
    reg [`LEN_BITS-1:0] len;      // working (possibly clamped) payload length
    reg [`LEN_BITS-1:0] scan_idx;
    reg        is_num, is_alnum, is_kanji;
    reg [5:0]  version;           // 1..40
    reg [5:0]  v_iter;            // version under test in S_SELECT
    reg [15:0] pbits_q;           // pbits(len, mode) - stable during the scan
    reg        v_maxed;
    reg [1:0]  mode;
    reg [32:0] blk;               // tbl_blocks latch
    reg [`LEN_BITS-1:0] k_pipe;
    reg              recompute;   // set when len shrinks; pbits_q updates next cycle

    wire [1:0] mode_now = (len == 0)          ? M_ALNUM :
                          is_kanji            ? M_KANJI :
                          is_num              ? M_NUM   :
                          is_alnum            ? M_ALNUM : M_BYTE;

    function [`LEN_BITS-1:0] div3;
        input [`LEN_BITS-1:0] n;
        reg [25:0] t;
        begin
            t = n * 14'd5462;          // 13-bit n * 14-bit M, max 26-bit product
            div3 = {1'b0, t[25:14]};   // floor(n * 5462 / 16384) = floor(n/3)
        end
    endfunction

    function [`LEN_BITS-1:0] kof;
        input [`LEN_BITS-1:0] n;
        input [1:0] m;
        begin
            kof = (m == M_ALNUM) ? (n >> 1) : div3(n);
        end
    endfunction

    function [15:0] pbits_k;
        input [`LEN_BITS-1:0] k;
        input [`LEN_BITS-1:0] n;
        input [1:0] m;
        reg [1:0] r;
        begin
            case (m)
                M_NUM: begin
                    r = n - 3 * k;         // 0..2 — uses registered k
                    pbits_k = 10 * k + ((r == 2) ? 16'd7 : (r == 1) ? 16'd4 : 16'd0);
                end
                M_ALNUM: begin
                    pbits_k = 11 * k + (n[0] ? 16'd6 : 16'd0);
                end
                M_KANJI: pbits_k = 13 * (n >> 1);
                default: pbits_k = {3'b0, n} * 8;
            endcase
        end
    endfunction

    function [15:0] pbits;
        input [`LEN_BITS-1:0] n;
        input [1:0] m;
        reg [`LEN_BITS-1:0] k;
        reg [1:0] r;
        begin
            case (m)
                M_NUM: begin
                    k = div3(n);          // DSP48; result registered in k_pipe
                    r = n - 3 * k;         // 0..2
                    pbits = 10 * k + ((r == 2) ? 16'd7 : (r == 1) ? 16'd4 : 16'd0);
                end
                M_ALNUM: begin
                    k = n / 2;
                    pbits = 11 * k + (n[0] ? 16'd6 : 16'd0);
                end
                M_KANJI: pbits = 13 * (n >> 1);
                default: pbits = {3'b0, n} * 8;
            endcase
        end
    endfunction

    function fits_v;
        input [15:0] pb;     // pbits(len, mode), registered
        input [5:0]  v;
        input [1:0]  m;
        input [1:0]  ec;
        reg [15:0] need;
        begin
            need = 16'd4 + {10'd0, tbl_cnt_bits(v, m)} + pb;
            fits_v = ({3'b0, tbl_data_cw(v, ec)} * 16'd8) >= need;
        end
    endfunction

    function [1:0] ec_fmt;               // ISO format-info EC bits
        input [1:0] ec;
        begin
            case (ec)
                2'd0: ec_fmt = 2'b01;    // L
                2'd1: ec_fmt = 2'b00;    // M
                2'd2: ec_fmt = 2'b11;    // Q
                default: ec_fmt = 2'b10; // H
            endcase
        end
    endfunction

    wire is_digit = (buf_rd_data >= 8'h30) && (buf_rd_data <= 8'h39);
    wire is_alnum_char =
        is_digit ||
        (buf_rd_data >= 8'h41 && buf_rd_data <= 8'h5A) ||
        (buf_rd_data == 8'h20) || (buf_rd_data == 8'h24) ||
        (buf_rd_data == 8'h25) || (buf_rd_data == 8'h2A) ||
        (buf_rd_data == 8'h2B) || (buf_rd_data == 8'h2D) ||
        (buf_rd_data == 8'h2E) || (buf_rd_data == 8'h2F) ||
        (buf_rd_data == 8'h3A);
    wire scan_hi = (scan_idx[0] == 1'b0);
    wire is_kanji_char =
        scan_hi ? ((buf_rd_data >= 8'h81 && buf_rd_data <= 8'h9F) ||
                   (buf_rd_data >= 8'hE0 && buf_rd_data <= 8'hEB))
                : ((buf_rd_data >= 8'h40 && buf_rd_data <= 8'h7E) ||
                   (buf_rd_data >= 8'h80 && buf_rd_data <= 8'hFC));

    assign buf_scan_en = (state == S_SCAN) && (scan_idx < len);

    always @(posedge clk) begin
        if (rst) begin
            state      <= S_IDLE;
            pack_start <= 1'b0;
            rs_start   <= 1'b0;
            mb_start   <= 1'b0;
            buf_rd_clr <= 1'b0;
            too_long   <= 1'b0;
            len        <= 0;
            scan_idx   <= 0;
            is_num     <= 1'b1;
            is_alnum   <= 1'b1;
            is_kanji   <= 1'b0;
            version    <= 6'd1;
            v_iter     <= 6'd1;
            pbits_q    <= 16'd0;
            pack_payload_bits <= 16'd0;
            v_maxed    <= 1'b0;
            mode       <= M_BYTE;
            k_pipe     <= {`LEN_BITS{1'b0}};
            recompute  <= 1'b0;
        end else begin
            pack_start <= 1'b0;
            rs_start   <= 1'b0;
            mb_start   <= 1'b0;
            buf_rd_clr <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        len      <= buf_length;
                        scan_idx <= 0;
                        is_num   <= 1'b1;
                        is_alnum <= 1'b1;
                        is_kanji <= ~buf_length[0];
                        v_maxed  <= 1'b0;
                        mode     <= (buf_length == 0) ? M_ALNUM : M_BYTE;
                        pbits_q  <= pbits(buf_length, (buf_length == 0) ? M_ALNUM : M_BYTE);
                        v_iter   <= 6'd1;
                        k_pipe   <= kof(buf_length, (buf_length == 0) ? M_ALNUM : M_BYTE);
                        state    <= (buf_length == 0) ? S_SELECT : S_SCAN;
                    end
                end

                S_SCAN: begin
                    if (scan_idx < len) begin
                        is_num   <= is_num   && is_digit;
                        is_alnum <= is_alnum && is_alnum_char;
                        is_kanji <= is_kanji && is_kanji_char;
                        scan_idx <= scan_idx + 1'b1;
                    end else begin
                        buf_rd_clr <= 1'b1;
                        mode       <= mode_now;
                        pbits_q    <= pbits(len, mode_now);
                        k_pipe     <= kof(len, mode_now);
                        v_iter     <= 6'd1;
                        state      <= S_SELECT;
                    end
                end

                S_SELECT: begin
                    if (fits_v(pbits_q, v_iter, mode, ec_level)) begin
                        version <= v_iter;
                        state   <= S_CFG;
                    end else if (v_iter == 6'd40 && !recompute && !v_maxed) begin
                        len     <= (len > `RS_MAX_DATA_CW) ? `RS_MAX_DATA_CW : len;
                        k_pipe  <= kof((len > `RS_MAX_DATA_CW) ? `RS_MAX_DATA_CW : len, mode);
                        v_maxed <= 1'b1;
                        v_iter  <= 6'd1;
                        recompute <= 1'b1;
                    end else if (v_iter == 6'd40 && !recompute) begin
                        len     <= (mode == M_KANJI) ? ((len - 2'd2) & ~{1'b1, 12'd0})
                                                     : (len - 13'd1);
                        k_pipe  <= kof((mode == M_KANJI) ? ((len - 2'd2) & ~{1'b1, 12'd0})
                                                          : (len - 13'd1), mode);
                        v_maxed <= 1'b1;
                        v_iter  <= 6'd1;
                        recompute <= 1'b1;
                    end else if (recompute) begin
                        pbits_q   <= pbits_k(k_pipe, len, mode);
                        recompute <= 1'b0;
                    end else begin
                        v_iter <= v_iter + 6'd1;
                    end
                end

                S_CFG: begin
                    blk       <= tbl_blocks(version, ec_level);
                    pack_mode <= mode;
                    pack_len  <= len;
                    pack_cnt_w<= tbl_cnt_bits(version, mode);
                    pack_payload_bits <= pbits_q;
                    state     <= S_LAUNCH;
                end

                S_LAUNCH: begin
                    pack_data_cw <= tbl_data_cw(version, ec_level);
                    pack_start   <= 1'b1;

                    rs_d1     <= blk[32:26];
                    rs_n1     <= blk[25:19];
                    rs_d2     <= blk[18:12];
                    rs_n2     <= blk[11:5];
                    rs_parity <= blk[4:0];
                    rs_start  <= 1'b1;

                    mb_version  <= version;
                    mb_size     <= 8'd17 + {2'b00, version, 2'b00};
                    mb_total_cw <= tbl_total_cw(version, ec_level);
                    mb_ec_fmt   <= ec_fmt(ec_level);
                    mb_start    <= 1'b1;
                    too_long    <= v_maxed;
                    state       <= S_RUN;
                end

                S_RUN: begin
                    if (mb_done) begin
                        too_long <= 1'b0;
                        state    <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
