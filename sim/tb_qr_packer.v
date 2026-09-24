`timescale 1ns/1ps
`include "qvision_config.vh"
module tb_qr_packer;
    reg clk = 0;
    reg rst = 1;
    always #5 clk = ~clk;   // 100 MHz

    reg        in_valid = 0;
    reg [7:0]  in_byte  = 0;
    reg        commit   = 0;
    reg        start    = 0;
    wire [7:0] rd_data;
    wire       rd_en;
    wire [`LEN_BITS-1:0] length;
    wire       committed_flag, overflow_flag;
    wire [7:0] cw_data;
    wire       cw_valid, pack_done;

    reg [1:0]  mode = 2'd0;
    reg [4:0]  cnt_w = 5'd8;
    reg [`LEN_BITS-1:0] data_cw = 16;
    reg [15:0] payload_bits = 16'd0;

    qr_buf u_buf (
        .clk(clk), .rst(rst),
        .in_byte(in_byte), .in_valid(in_valid),
        .commit(commit), .clear(1'b0), .rd_clr(1'b0),
        .rd_data(rd_data), .rd_en(rd_en),
        .length(length), .committed_flag(committed_flag),
        .overflow_flag(overflow_flag)
    );

    qr_encoder dut (
        .clk(clk), .rst(rst), .start(start),
        .payload_length(length),
        .mode(mode),
        .cnt_w(cnt_w),
        .data_cw(data_cw),
        .payload_bits(payload_bits),
        .buf_rd_data(rd_data),
        .buf_rd_en(rd_en),
        .cw_data(cw_data),
        .cw_valid(cw_valid),
        .done(pack_done)
    );

    integer len = 5;
    integer i, n_cw, k;
    reg [7:0] cw [0:`RS_MAX_DATA_CW-1];
    reg [8*45-1:0] alnum_rom;
    reg [7:0] alnum_set [0:44];

    initial begin
        alnum_rom = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";
        for (k = 0; k < 45; k = k + 1)
            alnum_set[k] = alnum_rom[8*(44-k) +: 8];
    end

    initial begin
        if (!$value$plusargs("PLEN=%d", len)) len = 5;
        void'($value$plusargs("MODE=%d", mode));
        void'($value$plusargs("CNTW=%d", cnt_w));
        void'($value$plusargs("DATA_CW=%d", data_cw));
        case (mode)
            2'd1: payload_bits = (len / 3) * 10 +
                                 ((len % 3 == 2) ? 7 : (len % 3 == 1) ? 4 : 0);
            2'd2: payload_bits = (len / 2) * 11 + ((len % 2) ? 6 : 0);
            2'd3: payload_bits = (len / 2) * 13;
            default: payload_bits = len * 8;
        endcase
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (4) @(posedge clk);

        for (i = 0; i < len; i = i + 1) begin
            @(posedge clk);
            in_valid <= 1'b1;
            if (mode == 2'd1)      in_byte <= 8'h30 + i % 10;          // digits
            else if (mode == 2'd2) in_byte <= alnum_set[i % 45];       // full alnum alphabet
            else if (mode == 2'd3) begin
                in_byte <= (i[0] == 1'b0) ? (8'h82 + (i >> 1) % 8)
                                          : (8'h41 + i % 40);
            end
            else                   in_byte <= 8'h41 + i[5:0];          // raw
        end
        @(posedge clk);
        in_valid <= 1'b0;
        repeat (4) @(posedge clk);

        @(posedge clk); commit <= 1'b1;
        @(posedge clk); commit <= 1'b0;
        wait (committed_flag === 1'b1);
        repeat (2) @(posedge clk);

        @(posedge clk); start <= 1'b1;
        @(posedge clk); start <= 1'b0;

        n_cw = 0;
        while (pack_done !== 1'b1) begin
            @(posedge clk);
            if (cw_valid === 1'b1 && n_cw < `RS_MAX_DATA_CW) begin
                cw[n_cw] = cw_data;
                n_cw = n_cw + 1;
            end
        end

        $write("CW ");
        for (i = 0; i < n_cw; i = i + 1) $write("%02x", cw[i]);
        $write("\n");
        $finish;
    end

    initial begin
        #100000000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
