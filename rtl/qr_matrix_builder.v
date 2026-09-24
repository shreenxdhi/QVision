`timescale 1ns/1ps
`include "qvision_config.vh"
module qr_matrix_builder (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [5:0]  version,        // 1..40 (drives the table lookups)
    input  wire [7:0]  size,           // 21 / 25 / ... / 177
    input  wire [`LEN_BITS-1:0] total_cw, // data + parity codewords
    input  wire [1:0]  ec_fmt,         // ISO format-info EC bits
    input  wire [7:0]  codeword_data,
    input  wire        codeword_valid,
    output reg  [`FB_ADDR_BITS-1:0] fb_addr,
    output reg         fb_din,
    output reg         fb_we,
    output reg         done
);
`include "qr_tables.vh"
`undef QR_TABLES_VH
    localparam [3:0] S_IDLE       = 4'd0,
                     S_FIND       = 4'd1,
                     S_TIMING     = 4'd2,
                     S_ALIGN_PAT  = 4'd3,
                     S_DARK       = 4'd4,
                     S_VERINFO    = 4'd5,
                     S_WAIT_CW    = 4'd6,
                     S_PLACE      = 4'd7,
                     S_EVAL       = 4'd8,
                     S_EVAL_SETUP = 4'd9,
                     S_FMT        = 4'd10,
                     S_COMMIT     = 4'd11,
                     S_DONE       = 4'd12,
                     S_EVAL_N4    = 4'd13,   // dark-ratio penalty settle
                     S_CLEAR      = 4'd14,   // deterministic RAM initialization
                     S_CLEAR_WAIT = 4'd15;   // settle size and arm write port

    reg [3:0] state;

    reg [7:0]  cfg_size;
    reg [5:0]  cfg_version;
    reg [`LEN_BITS-1:0] cfg_total_cw;
    reg [1:0]  cfg_ec_fmt;

    wire [11:0] cw_addr;
    wire [7:0] cw_q;
    reg [11:0] cw_read_addr;
    reg [7:0]  cw_shift;
    reg [1:0]  place_warm;
    reg [`LEN_BITS-1:0] cw_count;
    reg       collecting;
    reg [14:0] bit_idx;              // data-bit index during placement

    reg [14:0] clear_addr;

    wire [7:0]  size_m8 = cfg_size - 8'd8;        // dark-module row, format edge
    wire [14:0] total_bits = {3'b0, cfg_total_cw} * 13'd8;
    wire [15:0] total_sq_w = cfg_size * cfg_size;     // 177*177 = 31329
    reg  [15:0] total_sq_q;
    always @(posedge clk) begin
        if (rst) total_sq_q <= 16'd0;
        else     total_sq_q <= total_sq_w;
    end
    reg [2:0]  fp_idx, fp_x, fp_y;
    reg [7:0]  t_idx;
    reg        timing_phase;
    reg [2:0]  al_ri, al_ci;      // alignment grid: centre-row/-col indices
    reg [2:0]  al_dr, al_dc;
    reg [5:0]  vi_idx;            // cfg_version-info walk, 0..35

    wire [17:0] ver_info_bits = tbl_ver_info(cfg_version);
    wire [7:0] al_r = tbl_align_pos(cfg_version, al_ri);
    wire [7:0] al_c = tbl_align_pos(cfg_version, al_ci);
    wire al_skip = (al_r == 8'd6 && al_c == 8'd6) ||
                   (al_r == 8'd6 && al_c == cfg_size - 8'd7) ||
                   (al_r == cfg_size - 8'd7 && al_c == 8'd6);

    reg [7:0] pz_right, pz_vert;
    reg       pz_j, pz_up;
    reg       walking;
    reg       occ_q;
    reg [7:0] px_q, py_q;
    reg       px_valid_q;
    reg [7:0] wx_q, wy_q;   // position held for the write stage
    reg       px_valid_qq;  // write stage valid (occupancy computed)

    wire [7:0] pz_x      = pz_j ? (pz_right - 8'd1) : pz_right;
    wire [7:0] pz_y      = pz_up ? (cfg_size - 8'd1 - pz_vert) : pz_vert;


    reg [7:0] ev_i, ev_j;        // outer / inner scan index
    reg [`FB_ADDR_BITS-1:0] ev_addr_q; // incremental scan address
    reg       ev_pass;           // 0 = row scan, 1 = column scan
    reg [2:0] ev_mask;
    reg       ev_active;

    reg       p_valid, p_first, p_last, p_pass;
    reg       p_end, p_end_all, p_end_d, p_end_all_d;
    reg [7:0] p_r, p_c, p_pos;
    reg [2:0] p_mask, p_mask_d;
    reg       e_valid, e_first, e_last, e_pass;
    reg       e_end, e_end_all, e_cell;
    reg [7:0] e_r, e_c, e_pos;
    reg [2:0] e_mask;

    reg [23:0] pen_cur;
    reg [23:0] best_pen;
    reg [7:0]  pen_delta_q;       // registered penalty delta (max 218)
    reg [2:0]  best_mask;
    reg [23:0] n4_pen_q;
    reg [2:0]  n4_st;
    reg [3:0]  n4_step_q;
    reg [22:0] n4_thresh_q;
    reg        mbit_cm_q;            // commit-pass mask lookahead
    reg        run_color;
    reg [7:0]  run_len;
    reg [10:0] window;
    reg [14:0] dark_cnt;
    reg        cur_prev;         // cell (r,   c-1)
    reg        prev_prev;        // cell (r-1, c-1)
    reg        prev_row [0:176]; // cell (r-1, c)
    integer    pi;

    reg  [`FB_ADDR_BITS-1:0] rd_addr;
    wire       mat_dout, map_dout;


    wire [2:0]  fmt_mask = p_valid ? p_mask : best_mask;
    wire [14:0] format_bits;
    qr_format_bch u_format (
        .ec_level    (cfg_ec_fmt),
        .mask_id     (fmt_mask),
        .format_bits (format_bits)
    );

    wire [7:0] la_r = ev_pass ? ev_j : ev_i;
    wire [7:0] la_c = ev_pass ? ev_i : ev_j;
    wire [1:0] la_r3  = la_r % 3;
    wire [1:0] la_c3  = la_c % 3;
    wire [1:0] la_rc3 = (la_r3 * la_c3) % 3;      // (r*c) % 3
    wire       la_m4  = ((la_r >> 1) + (la_c / 3)) % 2;
    reg        la_fmt_hit;
    reg [3:0]  la_fmt_idx;
    always @(*) begin
        la_fmt_hit = 1'b0;
        la_fmt_idx = 4'd0;
        if (la_c == 8'd8) begin
            if (la_r <= 8'd5)       begin la_fmt_hit = 1'b1; la_fmt_idx = la_r[3:0]; end
            else if (la_r == 8'd7)  begin la_fmt_hit = 1'b1; la_fmt_idx = 4'd6;       end
            else if (la_r == 8'd8)  begin la_fmt_hit = 1'b1; la_fmt_idx = 4'd7;       end
            else if (la_r >= size_m8 + 8'd1)
                                    begin la_fmt_hit = 1'b1; la_fmt_idx = la_r[3:0] + 4'd15 - cfg_size[3:0]; end
        end
        if (la_r == 8'd8) begin
            if (la_c == 8'd7)            begin la_fmt_hit = 1'b1; la_fmt_idx = 4'd8; end
            else if (la_c <= 8'd5)       begin la_fmt_hit = 1'b1; la_fmt_idx = 4'd14 - la_c[3:0]; end
            else if (la_c >= size_m8)    begin la_fmt_hit = 1'b1; la_fmt_idx = cfg_size[3:0] - 4'd1 - la_c[3:0]; end
        end
    end
    reg       mbit_q, fmt_hit_q;
    reg [3:0] fmt_idx_q;

    function mask_bit_fn;            // ISO 18004 mask definitions
        input [2:0] m;
        input       r0, c0;
        input [1:0] r3, c3, rc3;
        input       m4;
        reg  [1:0]  s3;
        reg         rp, s2;
        begin
            s3 = (r3 + c3) % 3;      // (r + c) % 3
            rp = r0 & c0;            // (r * c) % 2
            s2 = r0 ^ c0;            // (r + c) % 2
            case (m)
                3'd0: mask_bit_fn = (s2 == 1'b0);
                3'd1: mask_bit_fn = (r0 == 1'b0);
                3'd2: mask_bit_fn = (c3 == 2'd0);
                3'd3: mask_bit_fn = (s3 == 2'd0);
                3'd4: mask_bit_fn = (m4 == 1'b0);
                3'd5: mask_bit_fn = (rc3 == 2'd0) && (rp == 1'b0);
                3'd6: mask_bit_fn = (rc3[0] ^ rp) == 1'b0;
                3'd7: mask_bit_fn = (rc3[0] ^ s2) == 1'b0;
                default: mask_bit_fn = 1'b0;
            endcase
        end
    endfunction

    function is_occupied;
        input [7:0] cx, cy;
        input [7:0] sz;
        input [5:0] ver;
        integer ri, ci;
        reg [2:0] ridx, cidx;
        reg [7:0] pr, pc;
        reg occ;
        begin
            occ = 1'b0;
            if (cx <= 8'd8 && cy <= 8'd8)          occ = 1'b1;
            else if (cx >= sz - 8'd8 && cy <= 8'd8) occ = 1'b1;
            else if (cx <= 8'd8 && cy >= sz - 8'd8) occ = 1'b1;
            else if (cx == 8'd6 || cy == 8'd6)      occ = 1'b1;
            for (ri = 0; ri < 7; ri = ri + 1) begin
                ridx = ri[2:0];
                pr = tbl_align_pos(ver, ridx);
                for (ci = 0; ci < 7; ci = ci + 1) begin
                    cidx = ci[2:0];
                    pc = tbl_align_pos(ver, cidx);
                    if ((ri < tbl_nalign(ver)) &&
                        (ci < tbl_nalign(ver)) &&
                        !((pr == 8'd6 && pc == 8'd6) ||
                          (pr == 8'd6 && pc == sz - 8'd7) ||
                          (pr == sz - 8'd7 && pc == 8'd6)) &&
                        (cx + 8'd2 >= pc) && (cx <= pc + 8'd2) &&
                        (cy + 8'd2 >= pr) && (cy <= pr + 8'd2))
                        occ = 1'b1;
                end
            end
            if (ver >= 8'd7) begin
                if ((cy <= 8'd5) && (cx >= sz - 8'd11) && (cx <= sz - 8'd9))
                    occ = 1'b1;
                if ((cx <= 8'd5) && (cy >= sz - 8'd11) && (cy <= sz - 8'd9))
                    occ = 1'b1;
            end
            is_occupied = occ;
        end
    endfunction

    localparam [6:0] FINDER_EDGE = 7'b1111111;
    localparam [6:0] FINDER_MID  = 7'b1000001;
    localparam [6:0] FINDER_CORE = 7'b1011101;

    function finder_bit;             // 7x7 finder pattern rows
        input [2:0] row, col;
        begin
            case (row)
                3'd0: finder_bit = FINDER_EDGE[3'd6 - col];
                3'd1: finder_bit = FINDER_MID[3'd6 - col];
                3'd2: finder_bit = FINDER_CORE[3'd6 - col];
                3'd3: finder_bit = FINDER_CORE[3'd6 - col];
                3'd4: finder_bit = FINDER_CORE[3'd6 - col];
                3'd5: finder_bit = FINDER_MID[3'd6 - col];
                default: finder_bit = FINDER_EDGE[3'd6 - col];
            endcase
        end
    endfunction

    wire mbit    = mbit_q;
    wire raw_val = mat_dout ^ (map_dout & mbit);
    wire cell_v  = fmt_hit_q ? format_bits[fmt_idx_q] : raw_val;

    wire run_change = e_first || (e_cell != run_color);
    wire [7:0] run_next = run_change ? 8'd1 : (run_len + 8'd1);
    wire [10:0] window_n = {window[9:0], e_cell};
    wire n3_hit = (e_pos >= 8'd10) &&
                  (window_n == 11'b00001011101 || window_n == 11'b10111010000);
    wire n2_hit = !e_pass && (e_r != 8'd0) && (e_c != 8'd0) &&
                  (e_cell == cur_prev) && (e_cell == prev_prev) &&
                  (e_cell == prev_row[e_c]);

    reg  [14:0] dark_tot_q;
    reg  [22:0] half_thr_q;
    always @(posedge clk) begin
        if (rst) begin
            dark_tot_q <= 15'd0;
            half_thr_q <= 23'd0;
        end else begin
            dark_tot_q <= (e_valid && !e_pass) ? (dark_cnt + {14'd0, e_cell})
                                                : dark_cnt;
            half_thr_q <= {7'd0, total_sq_q} * 23'd50;
        end
    end
    reg  [22:0] dark_scaled_q;
    reg  [22:0] dark_dev;
    always @(posedge clk) begin
        if (rst) begin
            dark_scaled_q <= 23'd0;
            dark_dev      <= 23'd0;
        end else begin
            dark_scaled_q <= dark_tot_q * 23'd100;
            dark_dev      <= (dark_scaled_q >= half_thr_q)
                             ? (dark_scaled_q - half_thr_q)
                             : (half_thr_q - dark_scaled_q);
        end
    end

    wire [7:0] n1_delta = !e_valid ? 8'd0 :
                           (run_change && !e_first && run_len >= 8'd5)
                           ? (run_len - 8'd2) :
                           (e_last && !run_change && run_next >= 8'd5)
                           ? (run_next - 8'd2) : 8'd0;
    wire [7:0] n3_delta = (e_valid && n3_hit) ? 8'd40 : 8'd0;
    wire [7:0] n2_delta = (e_valid && n2_hit) ? 8'd3 : 8'd0;
    wire [7:0] pen_delta = (n1_delta + n3_delta) + n2_delta;
    reg [4:0] fmt_wi;
    reg [7:0] fmt_w_r, fmt_w_c;
    reg [3:0] fmt_w_i;
    always @(*) begin
        fmt_w_r = 8'd0; fmt_w_c = 8'd0; fmt_w_i = 4'd0;
        if (fmt_wi <= 5'd5) begin
            fmt_w_r = {5'b0, fmt_wi};            fmt_w_c = 8'd8; fmt_w_i = fmt_wi[3:0];
        end else if (fmt_wi == 5'd6) begin
            fmt_w_r = 8'd7;                      fmt_w_c = 8'd8; fmt_w_i = 4'd6;
        end else if (fmt_wi == 5'd7) begin
            fmt_w_r = 8'd8;                      fmt_w_c = 8'd8; fmt_w_i = 4'd7;
        end else if (fmt_wi == 5'd8) begin
            fmt_w_r = 8'd8;                      fmt_w_c = 8'd7; fmt_w_i = 4'd8;
        end else if (fmt_wi <= 5'd14) begin
            fmt_w_r = 8'd8;                      fmt_w_c = 8'd14 - {4'b0, fmt_wi}; fmt_w_i = fmt_wi[3:0];
        end else if (fmt_wi <= 5'd22) begin
            fmt_w_r = 8'd8;                      fmt_w_c = cfg_size - 8'd1 - {4'b0, fmt_wi} + 8'd15; fmt_w_i = fmt_wi - 5'd15;
        end else begin
            fmt_w_r = cfg_size - 8'd7 + {4'b0, fmt_wi} - 8'd23; fmt_w_c = 8'd8; fmt_w_i = fmt_wi - 5'd15;
        end
    end
    reg        cm_run;
    reg [`FB_ADDR_BITS-1:0] cm_cnt;
    reg [7:0]  cm_x, cm_y;
    reg        pipe_v1;
    reg [`FB_ADDR_BITS-1:0] pipe_addr1;

    wire [1:0] cm_r3  = cm_y % 3;
    wire [1:0] cm_c3  = cm_x % 3;
    wire [1:0] cm_rc3 = (cm_r3 * cm_c3) % 3;
    wire       cm_m4  = ((cm_y >> 1) + (cm_x / 3)) % 2;
    reg  [7:0] w_x, w_y;
    reg        mat_din, map_din;
    reg        mat_we,  map_we;
    wire [`FB_ADDR_BITS-1:0] draw_waddr = w_y * cfg_size + w_x;
    wire [`FB_ADDR_BITS-1:0] mat_waddr = (state == S_CLEAR)
                                             ? clear_addr : draw_waddr;
    wire cw_we = collecting && codeword_valid && (cw_count < `RS_MAX_TOTAL);

    assign cw_addr = cw_we ? cw_count[11:0] : cw_read_addr;

    qvision_ram_1x31329_dp mat_mem_u (
        .clk_a(clk), .we_a(mat_we), .addr_a(mat_waddr), .din_a(mat_din), .dout_a(),
        .clk_b(clk), .we_b(1'b0), .addr_b(rd_addr), .din_b(1'b0), .dout_b(mat_dout)
    );
    qvision_ram_1x31329_dp map_mem_u (
        .clk_a(clk), .we_a(map_we), .addr_a(mat_waddr), .din_a(map_din), .dout_a(),
        .clk_b(clk), .we_b(1'b0), .addr_b(rd_addr), .din_b(1'b0), .dout_b(map_dout)
    );
    qvision_ram_8x3706_dp cw_mem_u (
        .clk_a(clk), .we_a(cw_we), .addr_a(cw_addr), .din_a(codeword_data), .dout_a(),
        .clk_b(clk), .we_b(1'b0), .addr_b(cw_read_addr), .din_b(8'h00), .dout_b(cw_q)
    );

    always @(*) begin
        rd_addr = (state == S_EVAL) ? ev_addr_q : cm_cnt;
    end

    always @(posedge clk) begin
        if (rst)
            cw_count <= 13'd0;
        else if (state == S_IDLE && start)
            cw_count <= 13'd0;
        else if (cw_we)
            cw_count         <= cw_count + 13'd1;
    end
    wire       cw_bit  = cw_shift[7];

    always @(posedge clk) begin
        if (rst) begin
            state      <= S_IDLE;
            fb_we      <= 1'b0;
            fb_din     <= 1'b0;
            fb_addr    <= 15'd0;
            done       <= 1'b0;
            collecting <= 1'b0;
            mat_we     <= 1'b0;
            map_we     <= 1'b0;
            mat_din    <= 1'b0;
            map_din    <= 1'b0;
            w_x        <= 8'd0;
            w_y        <= 8'd0;
            ev_active  <= 1'b0;
            ev_pass    <= 1'b0;
            ev_i       <= 8'd0;
            ev_j       <= 8'd0;
            ev_addr_q  <= {`FB_ADDR_BITS{1'b0}};
            ev_mask    <= 3'd0;
            p_valid    <= 1'b0;
            p_end      <= 1'b0;
            p_end_all  <= 1'b0;
            p_end_d    <= 1'b0;
            p_end_all_d<= 1'b0;
            e_valid    <= 1'b0;
            e_first    <= 1'b0;
            e_last     <= 1'b0;
            e_pass     <= 1'b0;
            e_end      <= 1'b0;
            e_end_all  <= 1'b0;
            e_cell     <= 1'b0;
            e_r        <= 8'd0;
            e_c        <= 8'd0;
            e_pos      <= 8'd0;
            e_mask     <= 3'd0;
            cm_run     <= 1'b0;
            pipe_v1    <= 1'b0;
            fmt_wi     <= 5'd0;
            pen_cur    <= 24'd0;
            pen_delta_q <= 8'd0;
            best_pen   <= 24'hFFFFFF;
            best_mask  <= 3'd0;
            n4_pen_q   <= 24'd0;
            n4_st      <= 3'd0;
            n4_step_q  <= 4'd0;
            n4_thresh_q <= 23'd0;
            mbit_cm_q  <= 1'b0;
            run_len    <= 8'd1;
            run_color  <= 1'b0;
            window     <= 11'd0;
            dark_cnt   <= 15'd0;
            cur_prev   <= 1'b0;
            prev_prev  <= 1'b0;
            bit_idx    <= 15'd0;
            cw_read_addr <= 12'd0;
            cw_shift     <= 8'd0;
            place_warm   <= 2'd0;
            pz_right      <= 8'd0;
            pz_vert       <= 8'd0;
            pz_j          <= 1'b0;
            pz_up         <= 1'b0;
            walking       <= 1'b0;
            occ_q         <= 1'b0;
            px_q          <= 8'd0;
            py_q          <= 8'd0;
            px_valid_q    <= 1'b0;
            wx_q          <= 8'd0;
            wy_q          <= 8'd0;
            px_valid_qq   <= 1'b0;
            clear_addr    <= 15'd0;
        end else begin
            mat_we <= 1'b0;
            map_we <= 1'b0;
            fb_we  <= 1'b0;
            done   <= 1'b0;
            p_valid <= ev_active;
            p_first <= (ev_j == 8'd0);
            p_last  <= (ev_j == cfg_size - 8'd1);
            p_pass  <= ev_pass;
            p_mask  <= ev_mask;
            p_pos   <= ev_j;
            if (ev_pass) begin
                p_r <= ev_j;              // column scan: inner index = row
                p_c <= ev_i;
            end else begin
                p_r <= ev_i;
                p_c <= ev_j;
            end
            p_end       <= ev_active && ev_pass && (ev_i == cfg_size - 8'd1) && (ev_j == cfg_size - 8'd1);
            p_end_all   <= ev_active && ev_pass && (ev_i == cfg_size - 8'd1) &&
                           (ev_j == cfg_size - 8'd1) && (ev_mask == 3'd7);
            p_end_d     <= e_end;
            p_end_all_d <= e_end_all;
            p_mask_d    <= e_mask;
            mbit_q      <= mask_bit_fn(ev_mask[2:0], la_r[0], la_c[0],
                                       la_r3, la_c3, la_rc3, la_m4);
            fmt_hit_q   <= la_fmt_hit;
            fmt_idx_q   <= la_fmt_idx;
            e_valid     <= p_valid;
            e_first     <= p_first;
            e_last      <= p_last;
            e_pass      <= p_pass;
            e_end       <= p_end;
            e_end_all   <= p_end_all;
            e_cell      <= cell_v;
            e_r         <= p_r;
            e_c         <= p_c;
            e_pos       <= p_pos;
            e_mask      <= p_mask;
            pen_delta_q <= pen_delta;
            pen_cur     <= (p_end_d ? 24'd0 : pen_cur) + {16'd0, pen_delta_q};
            dark_cnt <= (p_end_d ? 15'd0 : dark_cnt) +
                        ((!e_pass && e_valid && e_cell) ? 15'd1 : 15'd0);
            if (p_end_d && pen_cur < best_pen) begin
                best_pen  <= pen_cur;
                best_mask <= p_mask_d;
            end
            if (e_valid) begin
                run_color     <= e_cell;
                run_len       <= run_next;
                window        <= window_n;
                cur_prev      <= e_cell;
                prev_prev     <= prev_row[e_c];
                prev_row[e_c] <= e_cell;
            end

            case (state)
                S_IDLE: begin
                    if (start) begin
                        cfg_size     <= size;
                        cfg_version  <= version;
                        cfg_total_cw <= total_cw;
                        cfg_ec_fmt   <= ec_fmt;
                        collecting   <= 1'b1;
                        clear_addr <= 15'd0;
                        state      <= S_CLEAR_WAIT;
                    end
                end

                S_CLEAR_WAIT: begin
                    clear_addr <= 15'd0;
                    mat_we     <= 1'b1;
                    map_we     <= 1'b1;
                    mat_din    <= 1'b0;
                    map_din    <= 1'b0;
                    state      <= S_CLEAR;
                end

                S_CLEAR: begin
                    mat_we  <= 1'b1;
                    map_we  <= 1'b1;
                    mat_din <= 1'b0;
                    map_din <= 1'b0;
                    if (clear_addr == total_sq_q[14:0] - 15'd1) begin
                        fp_idx <= 3'd0;
                        fp_x   <= 3'd0;
                        fp_y   <= 3'd0;
                        state  <= S_FIND;
                    end else begin
                        clear_addr <= clear_addr + 15'd1;
                    end
                end
                S_FIND: begin
                    case (fp_idx)
                        2'd0: begin w_x <= {5'b0, fp_x};            w_y <= {5'b0, fp_y}; end
                        2'd1: begin w_x <= cfg_size - 8'd7 + {5'b0, fp_x}; w_y <= {5'b0, fp_y}; end
                        default: begin w_x <= {5'b0, fp_x};         w_y <= cfg_size - 8'd7 + {5'b0, fp_y}; end
                    endcase
                    mat_din <= finder_bit(fp_y, fp_x);
                    mat_we  <= 1'b1;
                    if (fp_x == 3'd6) begin
                        fp_x <= 3'd0;
                        if (fp_y == 3'd6) begin
                            fp_y <= 3'd0;
                            if (fp_idx == 2'd2) begin
                                state        <= S_TIMING;
                                timing_phase <= 1'b0;
                                t_idx        <= 8'd8;
                            end else begin
                                fp_idx <= fp_idx + 3'd1;
                            end
                        end else begin
                            fp_y <= fp_y + 3'd1;
                        end
                    end else begin
                        fp_x <= fp_x + 3'd1;
                    end
                end
                S_TIMING: begin
                    mat_we <= 1'b1;
                    if (timing_phase == 1'b0) begin
                        w_x     <= t_idx;
                        w_y     <= 8'd6;
                        mat_din <= ~t_idx[0];
                        if (t_idx == cfg_size - 8'd9) begin
                            timing_phase <= 1'b1;
                            t_idx        <= 8'd8;
                        end else begin
                            t_idx <= t_idx + 8'd1;
                        end
                    end else begin
                        w_x     <= 8'd6;
                        w_y     <= t_idx;
                        mat_din <= ~t_idx[0];
                        if (t_idx == cfg_size - 8'd9) begin
                            state <= (tbl_nalign(cfg_version) != 3'd0) ? S_ALIGN_PAT : S_DARK;
                            al_ri <= 3'd0;
                            al_ci <= 3'd0;
                            al_dr <= 3'd0;
                            al_dc <= 3'd0;
                        end else begin
                            t_idx <= t_idx + 8'd1;
                        end
                    end
                end

                S_ALIGN_PAT: begin
                    if (!al_skip) begin
                        w_x     <= al_c - 8'd2 + {5'b0, al_dc};
                        w_y     <= al_r - 8'd2 + {5'b0, al_dr};
                        mat_din <= (al_dr == 3'd0) || (al_dr == 3'd4) ||
                                   (al_dc == 3'd0) || (al_dc == 3'd4) ||
                                   (al_dr == 3'd2 && al_dc == 3'd2);
                        mat_we  <= 1'b1;
                    end
                    if (al_dc == 3'd4) begin
                        al_dc <= 3'd0;
                        if (al_dr == 3'd4) begin
                            al_dr <= 3'd0;
                            if (al_ci == tbl_nalign(cfg_version) - 3'd1) begin
                                al_ci <= 3'd0;
                                if (al_ri == tbl_nalign(cfg_version) - 3'd1) begin
                                    state <= S_DARK;
                                end else begin
                                    al_ri <= al_ri + 3'd1;
                                end
                            end else begin
                                al_ci <= al_ci + 3'd1;
                            end
                        end else begin
                            al_dr <= al_dr + 3'd1;
                        end
                    end else begin
                        al_dc <= al_dc + 3'd1;
                    end
                end
                S_DARK: begin
                    w_x     <= 8'd8;
                    w_y     <= size_m8;
                    mat_din <= 1'b1;
                    mat_we  <= 1'b1;
                    state   <= (cfg_version >= 8'd7) ? S_VERINFO : S_WAIT_CW;
                    vi_idx  <= 6'd0;
                end

                S_VERINFO: begin
                    if (vi_idx < 6'd18) begin
                        w_x     <= cfg_size - 8'd11 + {5'b0, vi_idx % 3'd3};
                        w_y     <= {5'b0, vi_idx / 3'd3};
                        mat_din <= ver_info_bits[vi_idx];
                    end else begin
                        w_x     <= {5'b0, (vi_idx - 6'd18) / 3'd3};
                        w_y     <= cfg_size - 8'd11 + {5'b0, (vi_idx - 6'd18) % 3'd3};
                        mat_din <= ver_info_bits[vi_idx - 6'd18];
                    end
                    mat_we <= 1'b1;
                    if (vi_idx == 6'd35)
                        state <= S_WAIT_CW;
                    else
                        vi_idx <= vi_idx + 6'd1;
                end
                S_WAIT_CW: begin
                    if (cw_count == cfg_total_cw) begin
                        bit_idx       <= 15'd0;
                        pz_right      <= cfg_size - 8'd1;
                        pz_vert       <= 8'd0;
                        pz_j          <= 1'b0;
                        pz_up         <= 1'b1;
                        walking       <= 1'b0;
                        px_valid_q    <= 1'b0;
                        px_valid_qq   <= 1'b0;
                        occ_q         <= 1'b0;
                        wx_q          <= 8'd0;
                        wy_q          <= 8'd0;
                        cw_read_addr  <= 12'd0;
                        place_warm    <= 2'd2;
                        collecting    <= 1'b0;
                        state         <= S_PLACE;
                    end
                end
                S_PLACE: begin
                    if (place_warm != 2'd0) begin
                        place_warm <= place_warm - 2'd1;
                        px_valid_q  <= 1'b0;
                        px_valid_qq <= 1'b0;
                        if (place_warm == 2'd1) begin
                            cw_shift     <= cw_q;
                            cw_read_addr <= 12'd1;
                            walking      <= 1'b1;
                        end
                    end else begin
                        if (px_valid_qq) begin
                            if (!occ_q) begin
                                w_x     <= wx_q;
                                w_y     <= wy_q;
                                mat_din <= (bit_idx < total_bits) ? cw_bit : 1'b0;
                                mat_we  <= 1'b1;
                                map_din <= 1'b1;
                                map_we  <= 1'b1;
                                bit_idx <= bit_idx + 15'd1;
                                if (bit_idx[2:0] == 3'd7) begin
                                    cw_shift     <= cw_q;
                                    cw_read_addr <= cw_read_addr + 12'd1;
                                end else begin
                                    cw_shift <= {cw_shift[6:0], 1'b0};
                                end
                            end
                        end else if (!walking && !px_valid_q) begin
                            state <= S_EVAL_SETUP;
                        end

                        occ_q       <= px_valid_q
                                       ? is_occupied(px_q, py_q, cfg_size, cfg_version)
                                       : 1'b1;
                        wx_q        <= px_q;
                        wy_q        <= py_q;
                        px_valid_qq <= px_valid_q;

                        px_q       <= pz_x;
                        py_q       <= pz_y;
                        px_valid_q <= walking;

                        if (walking) begin
                            if (!pz_j) begin
                                pz_j <= 1'b1;
                            end else begin
                                pz_j <= 1'b0;
                                if (pz_vert == cfg_size - 8'd1) begin
                                    pz_vert <= 8'd0;
                                    pz_up   <= ~pz_up;
                                    if (pz_right == 8'd1) begin
                                        walking <= 1'b0;
                                    end else if (pz_right == 8'd8) begin
                                        pz_right <= 8'd5; // skip timing column 6
                                    end else begin
                                        pz_right <= pz_right - 8'd2;
                                    end
                                end else begin
                                    pz_vert <= pz_vert + 8'd1;
                                end
                            end
                        end
                    end
                end
                S_EVAL_SETUP: begin
                    ev_mask   <= 3'd0;
                    ev_pass   <= 1'b0;
                    ev_i      <= 8'd0;
                    ev_j      <= 8'd0;
                    ev_addr_q <= {`FB_ADDR_BITS{1'b0}};
                    ev_active <= 1'b1;
                    best_pen  <= 24'hFFFFFF;
                    best_mask <= 3'd0;
                    pen_cur   <= 24'd0;
                    dark_cnt  <= 15'd0;
                    run_len   <= 8'd1;
                    run_color <= 1'b0;
                    window    <= 11'd0;
                    cur_prev  <= 1'b0;
                    prev_prev <= 1'b0;
                    for (pi = 0; pi < 177; pi = pi + 1)
                        prev_row[pi] <= 1'b0;
                    state <= S_EVAL;
                end

                S_EVAL: begin
                    if (ev_j == cfg_size - 8'd1) begin
                        ev_j <= 8'd0;
                        if (ev_i == cfg_size - 8'd1) begin
                            ev_i <= 8'd0;
                            ev_addr_q <= {`FB_ADDR_BITS{1'b0}};
                            if (ev_pass == 1'b0) begin
                                n4_st <= 3'd0;
                                n4_step_q <= 4'd0;
                                state <= S_EVAL_N4;     // row pass complete
                            end else if (ev_mask == 3'd7) begin
                                ev_active <= 1'b0;          // all masks done
                            end else begin
                                ev_mask <= ev_mask + 3'd1;
                                ev_pass <= 1'b0;
                            end
                        end else begin
                            ev_i <= ev_i + 8'd1;
                            ev_addr_q <= ev_pass ? {{(`FB_ADDR_BITS-8){1'b0}}, ev_i} + 15'd1
                                                : ev_addr_q + 15'd1;
                        end
                    end else begin
                        ev_j <= ev_j + 8'd1;
                        ev_addr_q <= ev_addr_q + (ev_pass ? {{(`FB_ADDR_BITS-8){1'b0}}, cfg_size}
                                                             : 15'd1);
                    end

                    if (p_end_all_d) begin
                        fmt_wi <= 5'd0;
                        state  <= S_FMT;
                    end
                end

                S_EVAL_N4: begin
                    p_valid <= 1'b0;          // freeze the penalty pipeline
                    if (n4_st <= 3'd3) begin
                        n4_st <= n4_st + 3'd1;
                    end else if (n4_step_q == 4'd0) begin
                        n4_pen_q    <= 24'd0;
                        n4_thresh_q <= ({7'd0, total_sq_q} << 2) +
                                       {7'd0, total_sq_q};
                        n4_step_q   <= 4'd1;
                    end else if (n4_step_q <= 4'd10) begin
                        if (dark_dev >= n4_thresh_q)
                            n4_pen_q <= n4_pen_q + 24'd10;
                        n4_thresh_q <= n4_thresh_q +
                                       (({7'd0, total_sq_q} << 2) +
                                        {7'd0, total_sq_q});
                        n4_step_q <= n4_step_q + 4'd1;
                    end else begin
                        pen_cur <= pen_cur + n4_pen_q;
                        ev_pass <= 1'b1;
                        ev_addr_q <= {`FB_ADDR_BITS{1'b0}};
                        state   <= S_EVAL;
                    end
                end
                S_FMT: begin
                    w_x     <= fmt_w_c;
                    w_y     <= fmt_w_r;
                    mat_din <= format_bits[fmt_w_i];
                    mat_we  <= 1'b1;
                    if (fmt_wi == 5'd29) begin
                        cm_cnt <= 15'd0;
                        cm_x   <= 8'd0;
                        cm_y   <= 8'd0;
                        cm_run <= 1'b1;
                        state  <= S_COMMIT;
                    end else begin
                        fmt_wi <= fmt_wi + 5'd1;
                    end
                end
                S_COMMIT: begin
                    pipe_v1    <= cm_run;
                    pipe_addr1 <= cm_cnt;
                    mbit_cm_q  <= mask_bit_fn(best_mask, cm_y[0], cm_x[0],
                                              cm_r3, cm_c3, cm_rc3, cm_m4);
                    if (cm_run) begin
                        if (cm_cnt == total_sq_q - 16'd1) begin
                            cm_run <= 1'b0;
                        end else begin
                            cm_cnt <= cm_cnt + 15'd1;
                            if (cm_x == cfg_size - 8'd1) begin
                                cm_x <= 8'd0;
                                cm_y <= cm_y + 8'd1;
                            end else begin
                                cm_x <= cm_x + 8'd1;
                            end
                        end
                    end
                    fb_we   <= pipe_v1;
                    fb_addr <= pipe_addr1;
                    fb_din  <= mat_dout ^ (map_dout & mbit_cm_q);
                    if (!cm_run && !pipe_v1)
                        state <= S_DONE;
                end

                S_DONE: begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
