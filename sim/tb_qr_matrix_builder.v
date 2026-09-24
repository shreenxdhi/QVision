`timescale 1ns/1ps
`include "qvision_config.vh"
module tb_qr_matrix_builder;
    reg clk = 0;
    reg rst = 1;
    always #5 clk = ~clk;   // 100 MHz

    reg        start = 0;
    reg [7:0]  cw_data = 0;
    reg        cw_valid = 0;
    wire [`FB_ADDR_BITS-1:0] fb_addr;
    wire        fb_din, fb_we, done;

    reg [5:0]  ver = 6'd1;
    reg [7:0]  size = 8'd21;
    reg [`LEN_BITS-1:0] total_cw = 26;
    reg [1:0]  ec_fmt = 2'b00;

    qr_matrix_builder dut (
        .clk(clk), .rst(rst), .start(start),
        .version(ver), .size(size),
        .total_cw(total_cw), .ec_fmt(ec_fmt),
        .codeword_data(cw_data), .codeword_valid(cw_valid),
        .fb_addr(fb_addr), .fb_din(fb_din), .fb_we(fb_we),
        .done(done)
    );

    reg fb [0:`FB_DEPTH-1];
    integer i, n;
    always @(posedge clk) begin
        if (fb_we && fb_addr < `FB_DEPTH)
            fb[fb_addr] <= fb_din;
    end

    reg [8*3706-1:0] cw_vec;      // up to RS_MAX_TOTAL codewords
    reg [31328:0] mat_vec;        // 177*177 module bits (fixed width: %h

    initial begin
        void'($value$plusargs("VER=%d", ver));
        size = 8'd17 + {2'b00, ver, 2'b00};
        void'($value$plusargs("TOTALCW=%d", total_cw));
        void'($value$plusargs("ECFMT=%d", ec_fmt));
        if (!$value$plusargs("CW=%h", cw_vec)) begin
            $display("ERROR: +CW=<hex> required");
            $finish;
        end
        for (i = 0; i < `FB_DEPTH; i = i + 1) fb[i] = 1'b0;

        repeat (4) @(posedge clk);
        rst = 0;
        repeat (4) @(posedge clk);

        @(posedge clk); start <= 1'b1;
        @(posedge clk); start <= 1'b0;

        n = total_cw;
        for (i = 0; i < n; i = i + 1) begin
            @(posedge clk);
            cw_data  <= cw_vec >> (8*n - 8 - 8*i);
            cw_valid <= 1'b1;
            @(posedge clk);
            cw_valid <= 1'b0;
        end

        wait (done === 1'b1);
        repeat (10) @(posedge clk);

        mat_vec = 0;
        for (i = 0; i < size*size; i = i + 1)
            mat_vec[size*size-1-i] = fb[i];

        $display("SIZE %0d", size);
        $display("MASK %0d", dut.best_mask);
        $write("MATRIX ");
        $write("%h", mat_vec);
        $write("\n");
        $finish;
    end

    initial begin
        #2000000000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
