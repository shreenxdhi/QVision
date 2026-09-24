`timescale 1ns/1ps
`include "qvision_config.vh"
module tb_rs2;
    reg clk=0, rst=1, start=0;
    reg [6:0] cfg_d1 = 7'd16, cfg_d2 = 7'd16;
    reg [6:0] cfg_n1 = 7'd1,  cfg_n2 = 7'd0;
    reg [4:0] cfg_parity = 5'd10;
    reg [7:0] data_in = 0;
    reg data_valid = 0;
    wire [7:0] cw_out; wire cw_valid, done;
    always #5 clk=~clk;
    qr_rs_encoder dut(.clk(clk),.rst(rst),.start(start),
        .cfg_d1(cfg_d1),.cfg_d2(cfg_d2),.cfg_n1(cfg_n1),.cfg_n2(cfg_n2),
        .cfg_parity(cfg_parity),
        .data_in(data_in),.data_valid(data_valid),
        .cw_out(cw_out),.cw_valid(cw_valid),.done(done));
    reg [8*3000-1:0] dvec = 0;
    integer i, n, nd;
    initial begin
        void'($value$plusargs("D1=%d", cfg_d1));
        void'($value$plusargs("N1=%d", cfg_n1));
        void'($value$plusargs("D2=%d", cfg_d2));
        void'($value$plusargs("N2=%d", cfg_n2));
        void'($value$plusargs("ECC=%d", cfg_parity));
        if (!$value$plusargs("DATA=%h", dvec)) begin $display("need DATA"); $finish; end
        void'($value$plusargs("ND=%d", nd));
        repeat (4) @(posedge clk); rst=0; repeat (4) @(posedge clk);
        @(posedge clk); start<=1; @(posedge clk); start<=0;
        for (i=0;i<nd;i=i+1) begin
            @(posedge clk); data_in<=dvec >> (8*nd - 8 - 8*i); data_valid<=1;
        end
        @(posedge clk); data_valid<=0;
        n=0;
        while (done !== 1'b1 && n < 5000) begin
            @(posedge clk);
            if (cw_valid===1'b1) begin $write("%02x", cw_out); n=n+1; end
        end
        $write("\nN=%0d\n", n);
        $finish;
    end
    initial begin
        #50000000;
        $display("TBTIMEOUT st=%0d n=%0d", dut.state, n);
        $finish;
    end
endmodule
