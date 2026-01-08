`timescale 1ns / 1ps
module tb_vga_timing;
    reg  clk;
    reg  rst;
    wire hs, vs, de;
    wire [9:0] x, y;
    integer hs_low, h_total, active_h_pixels;
    integer vs_low, v_total, active_v_lines;
    initial begin
        clk = 1'b0;
        forever #20 clk = ~clk;
    end
    vga_timing dut (
        .pix_clk(clk),
        .rst(rst),
        .hs(hs),
        .vs(vs),
        .de(de),
        .x(x),
        .y(y)
    );
    initial begin
        rst = 1'b1;
        repeat (10) @(posedge clk);
        rst = 1'b0;
    end
    task measure_horizontal;
        begin
            @(posedge de); 
            hs_low = 0;
            h_total = 0;
            active_h_pixels = 0;
            repeat (800) begin
                @(posedge clk);
                h_total = h_total + 1;
                if (hs == 1'b0) hs_low = hs_low + 1;
                if (de == 1'b1) active_h_pixels = active_h_pixels + 1;
            end
            $display("Horizontal: total=%0d, HS_low=%0d, active=%0d",
                      h_total, hs_low, active_h_pixels);
            if (h_total != 800) begin $display("ERROR: H_TOTAL != 800"); $finish; end
            if (hs_low  != 96 ) begin $display("ERROR: HS_LOW  != 96");  $finish; end
            if (active_h_pixels != 640) begin $display("ERROR: ACTIVE_H != 640"); $finish; end
        end
    endtask
    task measure_vertical;
        integer line, pix;
        reg de_seen;
        begin
            @(negedge vs); 
            vs_low = 0;
            v_total = 0;
            active_v_lines = 0;
            for (line = 0; line < 525; line = line + 1) begin
                de_seen = 0;
                for (pix = 0; pix < 800; pix = pix + 1) begin
                    @(posedge clk);
                    if (de) de_seen = 1;
                end
                if (vs == 1'b0) vs_low = vs_low + 1;  
                if (de_seen) active_v_lines = active_v_lines + 1;
                v_total = v_total + 1;
            end
            $display("Vertical: total=%0d, VS_low=%0d, active=%0d",
                      v_total, vs_low, active_v_lines);
            if (v_total != 525) begin $display("ERROR: V_TOTAL != 525"); $finish; end
            if (vs_low  != 2)   begin $display("ERROR: VS_LOW  != 2");   $finish; end
            if (active_v_lines != 480) begin $display("ERROR: ACTIVE_V != 480"); $finish; end
        end
    endtask
    initial begin
        $display("Starting VGA timing testbench...");
        @(negedge rst);
        repeat (5) @(posedge clk);
        measure_horizontal();
        measure_vertical();
        $display("VGA timing test PASSED perfectly (640x480@60 Hz).");
        $finish;
    end
    initial begin
        #50_000_000;
        $display("ERROR: TIMEOUT.");
        $finish;
    end
endmodule 