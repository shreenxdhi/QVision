`timescale 1ns/1ps
module tb_qr_matrix_builder;
    reg clk, rst, start;
    reg [7:0] codeword_data;
    reg codeword_valid;
    wire [8:0] fb_addr;
    wire fb_din, fb_we, done;
    reg framebuffer [0:440];
    integer i;
    initial begin
        clk = 0;
        forever #5 clk = ~clk;   
    end
    qr_matrix_builder dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .codeword_data(codeword_data),
        .codeword_valid(codeword_valid),
        .fb_addr(fb_addr),
        .fb_din(fb_din),
        .fb_we(fb_we),
        .done(done)
    );
    integer writes = 0;
    always @(posedge clk) begin
        if (fb_we && fb_addr < 441) begin
            framebuffer[fb_addr] <= fb_din;
            writes = writes + 1;
        end
    end
    initial begin
        $display("Starting QR matrix builder test...");
        for (i = 0; i < 441; i = i + 1)
            framebuffer[i] = 1'b0;
        rst = 1;
        start = 0;
        codeword_data = 0;
        codeword_valid = 0;
        #20 rst = 0;
        #20 start = 1;
        #10 start = 0;
        
        // Feed 26 dummy bytes
        for (i = 0; i < 26; i = i + 1) begin
            #20;
            codeword_data = i;
            codeword_valid = 1;
            #10;
            codeword_valid = 0;
        end
        
        wait(done);
        #100;
        $display("Simulation complete: Matrix drawn");
        if (writes == 392) begin
            $display("STATUS: *** PASS *** (All 392 modules written)");
        end else begin
            $display("STATUS: *** FAIL *** (Expected 392 pixels written, got %0d)", writes);
        end
        $finish;
    end
endmodule
