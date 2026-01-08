`include "qvision_config.vh"
module qvision_top (
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
    reset_sync rst_sync_inst (
        .clk(clk_in),
        .rst_n(rst_n),
        .sync_rst(sync_rst)
    );
    wire [7:0] uart_data;
    wire uart_valid;
    wire uart_framing_error;
    wire uart_overflow;
    uart_rx #(
        .CLK_HZ(`CLK_IN_HZ),
        .BAUD(`UART_BAUD)
    ) uart_rx_inst (
        .clk(clk_in),
        .rst(sync_rst),
        .rx(uart_rx),
        .data(uart_data),
        .valid(uart_valid),
        .framing_error(uart_framing_error),
        .overflow(uart_overflow)
    );
    wire [7:0] buf_rd_data;
    wire       buf_rd_en;
    wire [7:0] buf_length;
    wire       buf_committed;
    reg        buf_clear;
    reg pipeline_busy;
    wire matrix_done_pulse;
    reg matrix_done_prev;
    assign matrix_done_pulse = matrix_done && !matrix_done_prev;
    qr_buf qr_buf_inst (
        .clk(clk_in),
        .rst(sync_rst),
        .in_byte(uart_data),
        .in_valid(uart_valid),
        .commit(btn_commit),
        .clear(buf_clear),
        .rd_data(buf_rd_data),
        .rd_en(buf_rd_en),
        .length(buf_length),
        .committed_flag(buf_committed)
    );
    wire [7:0] encoder_codeword;
    wire       encoder_valid;
    wire       encoder_done;
    reg        encoder_start;
    reg        buf_committed_prev;
    reg        encoder_done_prev;
    wire       encoder_done_pulse;
    assign encoder_done_pulse = encoder_done && !encoder_done_prev;
    always @(posedge clk_in) begin
        if (sync_rst) begin
            buf_committed_prev <= 1'b0;
            encoder_start <= 1'b0;
            encoder_done_prev <= 1'b0;
            matrix_done_prev <= 1'b0;
            pipeline_busy <= 1'b0;
            buf_clear <= 1'b0;
        end else begin
            buf_committed_prev <= buf_committed;
            encoder_done_prev <= encoder_done;
            matrix_done_prev <= matrix_done;
            buf_clear <= 1'b0;  
            if (btn_clear) begin
                buf_clear <= 1'b1;
                pipeline_busy <= 1'b0;
            end
            else if (matrix_done_pulse) begin
                buf_clear <= 1'b1;
                pipeline_busy <= 1'b0;
            end
            if (buf_committed && !buf_committed_prev && !pipeline_busy) begin
                encoder_start <= 1'b1;
                pipeline_busy <= 1'b1;
            end else begin
                encoder_start <= 1'b0;
            end
        end
    end
    qr_encoder qr_encoder_inst (
        .clk(clk_in),
        .rst(sync_rst),
        .start(encoder_start),
        .payload_length(buf_length),
        .buf_rd_data(buf_rd_data),
        .buf_rd_en(buf_rd_en),
        .codeword_data(encoder_codeword),
        .codeword_valid(encoder_valid),
        .done(encoder_done)
    );
    wire [7:0] rs_codeword;
    wire       rs_valid;
    wire       rs_done;
    reg        rs_start;
    always @(posedge clk_in) begin
        if (sync_rst)
            rs_start <= 1'b0;
        else
            rs_start <= encoder_start;
    end
    qr_rs_encoder qr_rs_encoder_inst (
        .clk(clk_in),
        .rst(sync_rst),
        .start(rs_start),
        .data_in(encoder_codeword),
        .data_valid(encoder_valid),
        .parity_out(rs_codeword),
        .parity_valid(rs_valid),
        .done(rs_done)
    );
    wire [8:0] fb_wr_addr;
    wire       fb_wr_din;
    wire       fb_wr_we;
    wire       matrix_done;
    reg        matrix_start;
    always @(posedge clk_in) begin
        if (sync_rst) begin
            matrix_start <= 1'b0;
        end else begin
            matrix_start <= encoder_start;  
        end
    end
    qr_matrix_builder qr_matrix_builder_inst (
        .clk(clk_in),
        .rst(sync_rst),
        .start(matrix_start),
        .codeword_data(rs_codeword),
        .codeword_valid(rs_valid),
        .fb_addr(fb_wr_addr),
        .fb_din(fb_wr_din),
        .fb_we(fb_wr_we),
        .done(matrix_done)
    );
    wire [8:0] fb_rd_addr;
    wire       fb_rd_dout;
    qr_framebuffer qr_framebuffer_inst (
        .clka(clk_in),
        .addra(fb_wr_addr),
        .dina(fb_wr_din),
        .wea(fb_wr_we),
        .clkb(clk_in),
        .addrb(fb_rd_addr),
        .doutb(fb_rd_dout)
    );
    wire vga_de;
    wire [9:0] vga_x, vga_y;
    vga_timing vga_timing_inst (
        .pix_clk(clk_in),  
        .rst(sync_rst),
        .hs(vga_hs),
        .vs(vga_vs),
        .de(vga_de),
        .x(vga_x),
        .y(vga_y)
    );
    wire pixel_out;
    qr_pixel_mapper #(
        .MODULE_SCALE(6),
        .QUIET_ZONE(4)
    ) qr_pixel_mapper_inst (
        .pix_clk(clk_in),
        .rst(sync_rst),
        .de(vga_de),
        .x(vga_x),
        .y(vga_y),
        .fb_addr(fb_rd_addr),
        .fb_data(fb_rd_dout),
        .pixel_out(pixel_out)
    );
    rgb_dac_out #(
        .COLOR_BITS(`COLOR_BITS)
    ) rgb_dac_inst (
        .pixel_in(pixel_out),
        .r(vga_r),
        .g(vga_g), 
        .b(vga_b)
    );
    reg uart_activity_toggle;
    reg matrix_done_latch;  
    always @(posedge clk_in) begin
        if (sync_rst) begin
            uart_activity_toggle <= 1'b0;
            matrix_done_latch <= 1'b0;
        end else begin
            if (uart_valid) begin
                uart_activity_toggle <= ~uart_activity_toggle;
            end
            if (matrix_done)
                matrix_done_latch <= 1'b1;
            else if (buf_clear)
                matrix_done_latch <= 1'b0;
        end
    end
    assign led[0] = matrix_done_latch;       
    assign led[1] = uart_activity_toggle;    
    assign led[2] = buf_committed;           
    assign led[3] = uart_framing_error;      
endmodule
