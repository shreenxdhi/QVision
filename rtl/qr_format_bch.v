module qr_format_bch (
    input  wire [1:0] ec_level,    
    input  wire [2:0] mask_id,     
    output wire [14:0] format_bits 
);
    wire [4:0] data_bits = {ec_level, mask_id};
    parameter BCH_POLY = 11'b10100110111;
    reg [14:0] temp_data;
    reg [9:0] parity_bits;
    integer i;
    always @(*) begin
        temp_data = {data_bits, 10'b0};
        for (i = 14; i >= 10; i = i - 1) begin
            if (temp_data[i]) begin
                temp_data = temp_data ^ (BCH_POLY << (i - 10));
            end
        end
        parity_bits = temp_data[9:0];
    end
    wire [14:0] raw_format = {data_bits, parity_bits};
    parameter FORMAT_MASK = 15'b101010000010010;
    assign format_bits = raw_format ^ FORMAT_MASK;
endmodule
