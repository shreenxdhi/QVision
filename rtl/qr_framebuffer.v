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
    
    // Xilinx recommended template for true dual-port BRAM inference
    // A flat 1D array ensures safe asynchronous CDC simulation in ISim
    reg memory [0:TOTAL_BITS-1];

    always @(posedge clka) begin
        if (wea && (addra < TOTAL_BITS)) begin
            memory[addra] <= dina;
        end
    end

    always @(posedge clkb) begin
        if (addrb < TOTAL_BITS) begin
            doutb <= memory[addrb];
        end else begin
            doutb <= 1'b0;  
        end
    end

    integer i;
    initial begin
        for (i = 0; i < TOTAL_BITS; i = i + 1) begin
            memory[i] = 1'b0;
        end
    end
endmodule
