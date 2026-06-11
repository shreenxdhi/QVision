`timescale 1ns / 1ps
module tb_qr_format_bch;
    reg [1:0] ec_level;
    reg [2:0] mask_id;
    wire [14:0] format_bits;
    qr_format_bch dut (
        .ec_level(ec_level),
        .mask_id(mask_id),
        .format_bits(format_bits)
    );
    
    integer errors = 0;
    
    initial begin
        $display("Starting QR format BCH test...");
        
        // EC Level M (00), Mask 0
        ec_level = 2'b00; mask_id = 3'b000; #10;
        if (format_bits !== 15'b101010000010010) begin
            $display("FAIL: Expected 15'b101010000010010, got 15'b%b", format_bits);
            errors = errors + 1;
        end
        
        // EC Level M (00), Mask 1
        ec_level = 2'b00; mask_id = 3'b001; #10;
        if (format_bits !== 15'b101000100100101) begin
            $display("FAIL: Expected 15'b101000100100101, got 15'b%b", format_bits);
            errors = errors + 1;
        end
        
        if (errors == 0)
            $display("STATUS: *** PASS ***");
        else
            $display("STATUS: *** FAIL *** with %0d errors", errors);
            
        $finish;
    end
endmodule
