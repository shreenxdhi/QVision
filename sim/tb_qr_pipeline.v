`timescale 1ns/1ps
`include "qvision_config.vh"
module tb_qr_pipeline #(
    parameter [1:0] EC = 2'd1
)(
);
    reg clk_in;
    reg rst_n;
    reg uart_rx;
    reg btn_commit;
    reg btn_clear;
    wire vga_hs, vga_vs;
    wire [3:0] vga_r, vga_g, vga_b, led;

    localparam WIDE_BITS = 8*4096;      // full buffer depth (4096 bytes)

    initial begin
        clk_in = 0;
        forever #5 clk_in = ~clk_in;   // 100 MHz per qvision_config.vh
    end

    qvision_top #(.EC_LEVEL(EC)) dut (
        .clk_in(clk_in), .rst_n(rst_n),
        .uart_rx(uart_rx),
        .btn_commit(btn_commit), .btn_clear(btn_clear),
        .vga_hs(vga_hs), .vga_vs(vga_vs),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .led(led)
    );

    localparam real BIT_TIME = 1.0e9 / `UART_BAUD;   // ns

    task uart_send_byte;
        input [7:0] data;
        integer i;
        begin
            uart_rx = 0;                       // start bit
            #(BIT_TIME);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                #(BIT_TIME);
            end
            uart_rx = 1;                       // stop bit
            #(BIT_TIME);
        end
    endtask

    reg [WIDE_BITS-1:0] payload_hex;
    reg [31328:0] golden;                // 177*177 module bits, fixed width
    reg have_golden;
    integer plen, i;

    initial begin
        rst_n      = 0;
        uart_rx    = 1;
        btn_commit = 0;
        btn_clear  = 0;
        have_golden = $value$plusargs("GOLDEN=%h", golden);
        if (have_golden) begin
            begin : norm
                integer k, msb;
                msb = 0;
                for (k = 0; k < 31329; k = k + 1)
                    if (golden[k]) msb = k;
                golden = golden << (31328 - msb);
            end
        end
        if (!$value$plusargs("PAYLOAD=%h", payload_hex)) begin
            payload_hex = 48'h48454c4c4f;   // "HELLO"
            plen = 5;
        end else if (!$value$plusargs("PLEN=%d", plen)) begin
            plen = 5;
        end

        #100;
        rst_n = 1;
        #200;

        if ($value$plusargs("PRELOAD=%d", i) && i == 1) begin
            for (i = 0; i < plen; i = i + 1)
                dut.qr_buf_inst.buffer_u.mem[i] = payload_hex >> (8*(plen-1-i));
            dut.qr_buf_inst.wr_ptr = plen[12:0];
        end else begin
            for (i = plen - 1; i >= 0; i = i - 1)
                uart_send_byte(payload_hex >> (8*i));
            #(BIT_TIME * 2);
        end

        btn_commit = 1;
        #2000;
        btn_commit = 0;

        fork
            begin : wait_done
                wait (dut.matrix_done === 1'b1);
                disable wait_timeout;
            end
            begin : wait_timeout
                #100_000_000;   // 100 ms guard
                $display("[TIMEOUT] matrix_done never asserted");
                $display("STATUS FAIL");
                $finish;
            end
        join

        repeat (100) @(posedge clk_in);

        $display("SIZE %0d", dut.mb_size);
        $display("MASK %0d", dut.qr_matrix_builder_inst.best_mask);
        begin : dump
            reg [31328:0] mat;
            integer nsq;
            mat = 0;
            nsq = dut.mb_size;
            nsq = nsq * nsq;
            if ($test$plusargs("DEBUG_MEM")) begin
                $write("MAT\n");
                for (i = 0; i < nsq; i = i + 1)
                $write("%b", dut.qr_matrix_builder_inst.mat_mem_u.mem[i]);
                $write("\nMAP\n");
                for (i = 0; i < nsq; i = i + 1)
                    $write("%b", dut.qr_matrix_builder_inst.map_mem_u.mem[i]);
                $write("\n");
            end
            for (i = 0; i < nsq; i = i + 1)
                mat[31328-i] = dut.qr_framebuffer_inst.memory_u.mem[i];
            $write("MATRIX ");
            $write("%h", mat);
            $write("\n");
            if (have_golden) begin
                if (mat === golden)
                    $display("STATUS PASS");
                else
                    $display("STATUS FAIL");
            end
        end
        $finish;
    end

    initial begin
        #500_000_000;
        $display("[TIMEOUT] overall");
        $display("STATUS FAIL");
        $finish;
    end
endmodule
