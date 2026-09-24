`include "qvision_config.vh"
module qvision_top #(
    parameter [1:0] EC_LEVEL = 2'd1    // M
)(
    input  wire       clk_in,
    input  wire       rst_n,
    input  wire       uart_rx,
    input  wire       btn_commit,
    input  wire       btn_clear,
    output wire       vga_hs,
    output wire       vga_vs,
    output wire [3:0] vga_r,
    output wire [3:0] vga_g,
    output wire [3:0] vga_b,
    output wire [3:0] led
);
    wire sync_rst;
    wire pix_rst;
    wire pix_clk;
    wire pll_locked;
    wire rst_gated;
    wire pix_rst_base;
    (* ASYNC_REG = "TRUE" *) reg lock_sys_ff1, lock_sys_ff2;
    (* ASYNC_REG = "TRUE" *) reg lock_pix_ff1, lock_pix_ff2;

    wire btn_commit_pulse;
    wire btn_clear_pulse;

    wire [7:0] uart_data;
    wire uart_valid;
    wire uart_framing_error;

    wire [7:0] buf_rd_data;
    wire       buf_rd_en;
    wire       buf_rd_clr;
    wire [`LEN_BITS-1:0] buf_length;
    wire       buf_committed;
    wire       buf_overflow;
    wire       matrix_done;

    reg        ctrl_start;
    wire       ctrl_scan_en;
    wire       ctrl_too_long;
    wire       pack_buf_rd_en;

    wire [1:0] pack_mode;
    wire [4:0] pack_cnt_w;
    wire [`LEN_BITS-1:0] pack_len;
    wire [`LEN_BITS-1:0] pack_data_cw;
    wire [15:0] pack_payload_bits;
    wire       pack_start;
    wire [7:0] pack_cw_data;
    wire       pack_cw_valid;

    wire       rs_start, rs_done;
    wire [6:0] rs_d1, rs_d2, rs_n1, rs_n2;
    wire [4:0] rs_parity;
    wire [7:0] rs_cw_data;
    wire       rs_cw_valid;

    wire       mb_start;
    wire [5:0] mb_version;
    wire [7:0] mb_size;
    wire [`LEN_BITS-1:0] mb_total_cw;
    wire [1:0] mb_ec_fmt;

    wire [`FB_ADDR_BITS-1:0] fb_wr_addr;
    wire        fb_wr_din;
    wire        fb_wr_we;

    wire [`FB_ADDR_BITS-1:0] fb_rd_addr;
    wire        fb_rd_dout;

    wire vga_de;
    wire [9:0] vga_x, vga_y;
    wire pixel_out;
    wire hs_int, vs_int;
    reset_sync rst_sync_inst (
        .clk(clk_in),
        .rst_n(rst_n),
        .sync_rst(sync_rst)
    );
    pix_clk_gen pix_clk_gen_inst (
        .clk_in  (clk_in),
        .pix_clk (pix_clk),
        .locked  (pll_locked)
    );

    always @(posedge clk_in) begin
        if (sync_rst) begin
            lock_sys_ff1 <= 1'b0;
            lock_sys_ff2 <= 1'b0;
        end else begin
            lock_sys_ff1 <= pll_locked;
            lock_sys_ff2 <= lock_sys_ff1;
        end
    end
    always @(posedge pix_clk) begin
        if (pix_rst_base) begin
            lock_pix_ff1 <= 1'b0;
            lock_pix_ff2 <= 1'b0;
        end else begin
            lock_pix_ff1 <= pll_locked;
            lock_pix_ff2 <= lock_pix_ff1;
        end
    end

    assign rst_gated = sync_rst | ~lock_sys_ff2;
    reset_sync pix_rst_sync_inst (
        .clk(pix_clk),
        .rst_n(rst_n),
        .sync_rst(pix_rst_base)
    );
    assign pix_rst = pix_rst_base | ~lock_pix_ff2;
    (* ASYNC_REG = "TRUE" *) reg btn_commit_ff1, btn_commit_ff2;
    (* ASYNC_REG = "TRUE" *) reg btn_clear_ff1,  btn_clear_ff2;
    reg btn_commit_ff3, btn_clear_ff3;
    always @(posedge clk_in) begin
        if (rst_gated) begin
            btn_commit_ff1 <= 1'b0; btn_commit_ff2 <= 1'b0; btn_commit_ff3 <= 1'b0;
            btn_clear_ff1  <= 1'b0; btn_clear_ff2  <= 1'b0; btn_clear_ff3  <= 1'b0;
        end else begin
            btn_commit_ff1 <= btn_commit; btn_commit_ff2 <= btn_commit_ff1; btn_commit_ff3 <= btn_commit_ff2;
            btn_clear_ff1  <= btn_clear;  btn_clear_ff2  <= btn_clear_ff1;  btn_clear_ff3  <= btn_clear_ff2;
        end
    end
    assign btn_commit_pulse = btn_commit_ff2 & ~btn_commit_ff3;
    assign btn_clear_pulse  = btn_clear_ff2  & ~btn_clear_ff3;
    uart_rx #(
        .CLK_HZ(`CLK_IN_HZ),
        .BAUD(`UART_BAUD)
    ) uart_rx_inst (
        .clk(clk_in),
        .rst(rst_gated),
        .rx(uart_rx),
        .data(uart_data),
        .valid(uart_valid),
        .framing_error(uart_framing_error)
    );
    reg buf_clear;
    reg pipeline_busy;
    reg matrix_done_prev;
    reg [7:0] display_size;
    reg       display_ready;
    wire matrix_done_pulse = matrix_done && !matrix_done_prev;

    qr_buf qr_buf_inst (
        .clk(clk_in),
        .rst(rst_gated),
        .in_byte(uart_data),
        .in_valid(uart_valid),
        .commit(btn_commit_pulse),
        .clear(buf_clear),
        .rd_clr(buf_rd_clr),
        .rd_data(buf_rd_data),
        .rd_en(buf_rd_en),
        .length(buf_length),
        .committed_flag(buf_committed),
        .overflow_flag(buf_overflow)
    );
    reg buf_committed_prev;
    always @(posedge clk_in) begin
        if (rst_gated) begin
            buf_committed_prev <= 1'b0;
            ctrl_start         <= 1'b0;
            matrix_done_prev   <= 1'b0;
            pipeline_busy      <= 1'b0;
            buf_clear          <= 1'b0;
            display_size       <= 8'd0;
            display_ready      <= 1'b0;
        end else begin
            buf_committed_prev <= buf_committed;
            matrix_done_prev   <= matrix_done;
            buf_clear          <= 1'b0;

            if (ctrl_start)
                display_ready <= 1'b0;
            if (matrix_done_pulse) begin
                display_size  <= mb_size;
                display_ready <= 1'b1;
            end

            if ((btn_clear_pulse && !pipeline_busy) || matrix_done_pulse) begin
                buf_clear     <= 1'b1;
                pipeline_busy <= 1'b0;
            end

            if (buf_committed && !buf_committed_prev && !pipeline_busy) begin
                ctrl_start    <= 1'b1;
                pipeline_busy <= 1'b1;
            end else begin
                ctrl_start <= 1'b0;
            end
        end
    end

    qr_controller qr_controller_inst (
        .clk(clk_in),
        .rst(rst_gated),
        .start(ctrl_start),
        .buf_length(buf_length),
        .buf_rd_data(buf_rd_data),
        .buf_scan_en(ctrl_scan_en),
        .buf_rd_clr(buf_rd_clr),
        .ec_level(EC_LEVEL),
        .pack_start(pack_start),
        .pack_mode(pack_mode),
        .pack_len(pack_len),
        .pack_cnt_w(pack_cnt_w),
        .pack_data_cw(pack_data_cw),
        .pack_payload_bits(pack_payload_bits),
        .rs_start(rs_start),
        .rs_d1(rs_d1),
        .rs_d2(rs_d2),
        .rs_n1(rs_n1),
        .rs_n2(rs_n2),
        .rs_parity(rs_parity),
        .mb_start(mb_start),
        .mb_version(mb_version),
        .mb_size(mb_size),
        .mb_total_cw(mb_total_cw),
        .mb_ec_fmt(mb_ec_fmt),
        .mb_done(matrix_done),
        .too_long(ctrl_too_long)
    );

    assign buf_rd_en = pack_buf_rd_en | ctrl_scan_en;
    qr_encoder qr_encoder_inst (
        .clk(clk_in),
        .rst(rst_gated),
        .start(pack_start),
        .payload_length(pack_len),
        .mode(pack_mode),
        .cnt_w(pack_cnt_w),
        .data_cw(pack_data_cw),
        .payload_bits(pack_payload_bits),
        .buf_rd_data(buf_rd_data),
        .buf_rd_en(pack_buf_rd_en),
        .cw_data(pack_cw_data),
        .cw_valid(pack_cw_valid),
        .done()
    );
    qr_rs_encoder qr_rs_encoder_inst (
        .clk(clk_in),
        .rst(rst_gated),
        .start(rs_start),
        .cfg_d1(rs_d1),
        .cfg_d2(rs_d2),
        .cfg_n1(rs_n1),
        .cfg_n2(rs_n2),
        .cfg_parity(rs_parity),
        .data_in(pack_cw_data),
        .data_valid(pack_cw_valid),
        .cw_out(rs_cw_data),
        .cw_valid(rs_cw_valid),
        .done(rs_done)
    );
    qr_matrix_builder qr_matrix_builder_inst (
        .clk(clk_in),
        .rst(rst_gated),
        .start(mb_start),
        .version(mb_version),
        .size(mb_size),
        .total_cw(mb_total_cw),
        .ec_fmt(mb_ec_fmt),
        .codeword_data(rs_cw_data),
        .codeword_valid(rs_cw_valid),
        .fb_addr(fb_wr_addr),
        .fb_din(fb_wr_din),
        .fb_we(fb_wr_we),
        .done(matrix_done)
    );
    qr_framebuffer qr_framebuffer_inst (
        .clka(clk_in),
        .addra(fb_wr_addr),
        .dina(fb_wr_din),
        .wea(fb_wr_we),
        .clkb(pix_clk),
        .addrb(fb_rd_addr),
        .doutb(fb_rd_dout)
    );
    vga_timing vga_timing_inst (
        .pix_clk(pix_clk),
        .rst(pix_rst),
        .hs(hs_int),
        .vs(vs_int),
        .de(vga_de),
        .x(vga_x),
        .y(vga_y)
    );

    reg [1:0] hs_d, vs_d;
    always @(posedge pix_clk) begin
        if (pix_rst) begin
            hs_d <= 2'b11;
            vs_d <= 2'b11;
        end else begin
            hs_d <= {hs_d[0], hs_int};
            vs_d <= {vs_d[0], vs_int};
        end
    end
    assign vga_hs = hs_d[1];
    assign vga_vs = vs_d[1];
    qr_pixel_mapper #(
        .QUIET_ZONE(4)
    ) qr_pixel_mapper_inst (
        .pix_clk(pix_clk),
        .rst(pix_rst),
        .de(vga_de),
        .x(vga_x),
        .y(vga_y),
        .qr_size(display_size),
        .fb_addr(fb_rd_addr),
        .fb_data(fb_rd_dout),
        .pixel_out(pixel_out)
    );

    (* ASYNC_REG = "TRUE" *) reg display_ready_q1, display_ready_q2;
    reg display_ready_q3;
    always @(posedge pix_clk) begin
        if (pix_rst) begin
            display_ready_q1 <= 1'b0;
            display_ready_q2 <= 1'b0;
            display_ready_q3 <= 1'b0;
        end else begin
            display_ready_q1 <= display_ready;
            display_ready_q2 <= display_ready_q1;
            display_ready_q3 <= display_ready_q2;
        end
    end

    rgb_dac_out #(
        .COLOR_BITS(`COLOR_BITS)
    ) rgb_dac_inst (
        .pixel_in(pixel_out & display_ready_q3),
        .r(vga_r),
        .g(vga_g),
        .b(vga_b)
    );

    reg uart_activity_toggle;
    reg matrix_done_latch;
    always @(posedge clk_in) begin
        if (rst_gated) begin
            uart_activity_toggle <= 1'b0;
            matrix_done_latch    <= 1'b0;
        end else begin
            if (uart_valid)
                uart_activity_toggle <= ~uart_activity_toggle;
            if (matrix_done)
                matrix_done_latch <= 1'b1;
            else if (buf_clear)
                matrix_done_latch <= 1'b0;
        end
    end
    assign led[0] = matrix_done_latch;
    assign led[1] = uart_activity_toggle;
    assign led[2] = buf_overflow | ctrl_too_long;
    assign led[3] = uart_framing_error;
endmodule
