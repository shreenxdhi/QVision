module qr_framebuffer (
    input  wire       clka,
    input  wire [8:0] addra,    
    input  wire       dina,     
    input  wire       wea,
    input  wire       clkb,
    input  wire [8:0] addrb,
    output reg        doutb
);
    parameter TOTAL_BITS = 441;
    parameter BYTE_COUNT = 56;  
    reg [7:0] memory [0:BYTE_COUNT-1];
    function [5:0] get_byte_addr;
        input [8:0] bit_addr;
        begin
            get_byte_addr = bit_addr[8:3];  
        end
    endfunction
    function [2:0] get_bit_pos;
        input [8:0] bit_addr;
        begin
            get_bit_pos = bit_addr[2:0];    
        end
    endfunction
    always @(posedge clka) begin
        if (wea && (addra < TOTAL_BITS)) begin
            if (dina)
                memory[get_byte_addr(addra)][get_bit_pos(addra)] <= 1'b1;
            else
                memory[get_byte_addr(addra)][get_bit_pos(addra)] <= 1'b0;
        end
    end
    always @(posedge clkb) begin
        if (addrb < TOTAL_BITS) begin
            doutb <= memory[get_byte_addr(addrb)][get_bit_pos(addrb)];
        end else begin
            doutb <= 1'b0;  
        end
    end
    integer i;
    initial begin
        for (i = 0; i < BYTE_COUNT; i = i + 1) begin
            memory[i] = 8'h00;
        end
    end
endmodule
