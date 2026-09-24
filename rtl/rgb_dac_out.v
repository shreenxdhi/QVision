module rgb_dac_out #(
    parameter COLOR_BITS = 4
)(
    input  wire                    pixel_in,
    output wire [COLOR_BITS-1:0]  r,
    output wire [COLOR_BITS-1:0]  g,
    output wire [COLOR_BITS-1:0]  b
);
    wire [COLOR_BITS-1:0] max_val = {COLOR_BITS{1'b1}};
    wire [COLOR_BITS-1:0] zero_val = {COLOR_BITS{1'b0}};
    assign r = pixel_in ? zero_val : max_val;  
    assign g = pixel_in ? zero_val : max_val;  
    assign b = pixel_in ? zero_val : max_val;
endmodule
