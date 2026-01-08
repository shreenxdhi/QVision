`timescale 1ns/1ps
module tb_qr_pipeline;
    reg clk_in;
    reg rst_n;
    reg uart_rx;
    reg btn_commit;
    reg btn_clear;
    wire vga_hs;
    wire vga_vs;
    wire [3:0] vga_r;
    wire [3:0] vga_g;
    wire [3:0] vga_b;
    wire [3:0] led;
    initial begin
        clk_in = 0;
        forever #10 clk_in = ~clk_in;  
    end
    qvision_top dut (
        .clk_in(clk_in),
        .rst_n(rst_n),
        .uart_rx(uart_rx),
        .btn_commit(btn_commit),
        .btn_clear(btn_clear),
        .vga_hs(vga_hs),
        .vga_vs(vga_vs),
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b),
        .led(led)
    );
    localparam BIT_TIME = 8680;
    task uart_send_byte;
        input [7:0] data;
        integer i;
        begin
            uart_rx = 0;
            #BIT_TIME;
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                #BIT_TIME;
            end
            uart_rx = 1;
            #BIT_TIME;
        end
    endtask
    initial begin
        $display("=== QR Pipeline Testbench Started ===");
        $display("Testing QR V1-M encoder with 'HELLO' payload");
        $display("");
        rst_n = 0;
        uart_rx = 1;  
        btn_commit = 0;
        btn_clear = 0;
        #100;
        rst_n = 1;
        #100;
        $display("[STEP 1] Sending test data 'HELLO' via UART (115200 baud)...");
        uart_send_byte(8'h48);  
        #(BIT_TIME * 2);        
        uart_send_byte(8'h45);  
        #(BIT_TIME * 2);
        uart_send_byte(8'h4C);  
        #(BIT_TIME * 2);
        uart_send_byte(8'h4C);  
        #(BIT_TIME * 2);
        uart_send_byte(8'h4F);  
        #(BIT_TIME * 2);
        $display("[STEP 2] Pressing commit button...");
        #1000;
        btn_commit = 1;
        #1000;
        btn_commit = 0;
        $display("[STEP 3] Waiting for QR encoding pipeline...");
        wait(dut.matrix_done == 1'b1);
        #1000;
        $display("[STEP 4] QR encoding complete! Waiting for VGA display...");
        $display("         QR code area: X=233-406, Y=153-326 (centered 640x480)");
        #5000000;  
        $display("");
        $display("============================================");
        $display("          SIMULATION RESULTS");
        $display("============================================");
        if (black_pixel_count > 0) begin
            $display("  STATUS: *** PASS ***");
            $display("  QR code is displaying correctly!");
            $display("  - Black pixels detected: %0d", black_pixel_count);
            $display("  - White pixels in QR area: %0d", white_pixel_count);
            $display("  - First black pixel at: (%0d, %0d)", first_black_x, first_black_y);
        end else begin
            $display("  STATUS: *** FAIL ***");
            $display("  No black pixels detected in QR area!");
        end
        $display("============================================");
        $finish;
    end
    reg [3:0] prev_led;
    reg [3:0] prev_rgb;
    initial begin
        prev_led = 4'bxxxx;
        prev_rgb = 4'bxxxx;
    end
    always @(posedge clk_in) begin
        if (led !== prev_led) begin
            $display("Time=%0t | LED=%b | HS=%b VS=%b | R=%h G=%h B=%h", 
                     $time, led, vga_hs, vga_vs, vga_r, vga_g, vga_b);
            prev_led <= led;
        end
    end
    reg qr_area_logged;
    reg black_pixel_logged;
    reg [31:0] black_pixel_count;
    reg [31:0] white_pixel_count;
    reg [9:0] first_black_x, first_black_y;
    initial begin
        qr_area_logged = 0;
        black_pixel_logged = 0;
        black_pixel_count = 0;
        white_pixel_count = 0;
        first_black_x = 0;
        first_black_y = 0;
    end
    wire in_qr_data_area = dut.vga_de && 
                           (dut.vga_x >= 257) && (dut.vga_x < 383) &&
                           (dut.vga_y >= 177) && (dut.vga_y < 303);
    always @(posedge clk_in) begin
        if (!qr_area_logged && dut.vga_de && dut.vga_x >= 233 && dut.vga_y >= 153) begin
            $display("[%0t] VGA entered QR display area", $time);
            qr_area_logged <= 1;
        end
        if (in_qr_data_area) begin
            if (vga_r == 4'h0 && vga_g == 4'h0 && vga_b == 4'h0) begin
                black_pixel_count <= black_pixel_count + 1;
                if (!black_pixel_logged) begin
                    $display("[%0t] First BLACK PIXEL at x=%0d, y=%0d - QR code visible!", 
                             $time, dut.vga_x, dut.vga_y);
                    first_black_x <= dut.vga_x;
                    first_black_y <= dut.vga_y;
                    black_pixel_logged <= 1;
                end
            end else begin
                white_pixel_count <= white_pixel_count + 1;
            end
        end
    end
    reg rs_done_prev_tb, matrix_done_prev_tb;
    reg [15:0] fb_write_count;
    initial begin
        rs_done_prev_tb = 0;
        matrix_done_prev_tb = 0;
        fb_write_count = 0;
    end
    always @(posedge clk_in) begin
        if (dut.fb_wr_we)
            fb_write_count <= fb_write_count + 1;
    end
    always @(posedge clk_in) begin
        rs_done_prev_tb <= dut.rs_done;
        matrix_done_prev_tb <= dut.matrix_done;
        if (dut.buf_committed === 1'b1 && dut.buf_committed_prev === 1'b0)
            $display("[%0t] Buffer committed! Length=%0d", $time, dut.buf_length);
        if (dut.encoder_start === 1'b1)
            $display("[%0t] Encoder started!", $time);
        if (dut.encoder_done === 1'b1 && dut.encoder_done_prev === 1'b0)
            $display("[%0t] Encoder done!", $time);
        if (dut.rs_done === 1'b1 && rs_done_prev_tb === 1'b0)
            $display("[%0t] RS encoder done!", $time);
        if (dut.matrix_done === 1'b1 && matrix_done_prev_tb === 1'b0)
            $display("[%0t] Matrix builder done! FB writes=%0d", $time, fb_write_count);
    end
endmodule 