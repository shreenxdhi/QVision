`timescale 1ns/1ps
module tb_qr_rs_encoder;
    reg         clk, rst, start, data_valid;
    reg  [7:0]  data_in;
    wire [7:0]  parity_out;
    wire        parity_valid, done;
    qr_rs_encoder dut (
        .clk(clk), .rst(rst), .start(start),
        .data_in(data_in), .data_valid(data_valid),
        .parity_out(parity_out), .parity_valid(parity_valid), .done(done)
    );
    initial begin
        clk = 1'b0;
        forever #1 clk = ~clk;
    end
    reg [7:0] block   [0:15];
    reg [7:0] expected[0:9];   
    reg [7:0] got     [0:9];   
    integer i;
    integer pcount;
    integer ok, k;
    initial begin
        block[0]=8'h40; block[1]=8'h54; block[2]=8'h84; block[3]=8'h54;
        block[4]=8'hC4; block[5]=8'hC4; block[6]=8'hF0; block[7]=8'hEC;
        block[8]=8'h11; block[9]=8'hEC; block[10]=8'h11; block[11]=8'hEC;
        block[12]=8'h11; block[13]=8'hEC; block[14]=8'h11; block[15]=8'hEC;
        expected[0]=8'h23; expected[1]=8'h73; expected[2]=8'h23; expected[3]=8'h99;
        expected[4]=8'hEC; expected[5]=8'h08; expected[6]=8'hC9; expected[7]=8'hF7;
        expected[8]=8'h37; expected[9]=8'hDF;
        $display("=== QR RS Encoder Test: Version 1-M, 'HELLO' ===");
        rst        = 1'b1;
        start      = 1'b0;
        data_valid = 1'b0;
        data_in    = 8'h00;
        repeat (4) @(posedge clk);
        rst = 1'b0;
        @(posedge clk); start = 1'b1;
        @(posedge clk); start = 1'b0;
        for (i=0; i<16; i=i+1) begin
            @(posedge clk);
            data_in    <= block[i];
            data_valid <= 1'b1;
        end
        @(posedge clk);
        data_valid <= 1'b0;
        @(posedge clk); // added pipeline delay
        pcount = 0;
        while (done == 1'b0) begin
            @(posedge clk);
            if (parity_valid) begin
                got[pcount] = parity_out;
                $display("Parity[%0d] = 0x%02X", pcount, parity_out);
                if (parity_out !== expected[pcount])
                    $display("  MISMATCH: expected 0x%02X", expected[pcount]);
                pcount = pcount + 1;
            end
        end
        if (pcount == 10) begin
            ok = 1;
            for (k=0; k<10; k=k+1)
                if (got[k] !== expected[k]) ok = 0;
            if (ok)
                $display("PASS: 10 parity bytes match exactly (ISO 18004 transmission order).");
            else
                $display("FAIL: parity mismatch detected. Check byte order or data block.");
        end else begin
            $display("FAIL: expected 10 parity bytes, got %0d", pcount);
        end
        $finish;
    end
endmodule
