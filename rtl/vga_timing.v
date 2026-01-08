module vga_timing #(
    parameter H_ACTIVE    = 640,
    parameter H_FRONT     = 16,
    parameter H_SYNC      = 96,
    parameter H_BACK      = 48,
    parameter V_ACTIVE    = 480,
    parameter V_FRONT     = 10,
    parameter V_SYNC      = 2,
    parameter V_BACK      = 33
)(
    input  wire       pix_clk,      
    input  wire       rst,
    output reg        hs,           
    output reg        vs,           
    output reg        de,           
    output reg [9:0]  x,            
    output reg [9:0]  y             
);
    localparam H_TOTAL = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;  
    localparam V_TOTAL = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;  
    reg [9:0] h_count;
    reg [9:0] v_count;
    always @(posedge pix_clk) begin
        if (rst) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
            hs      <= 1'b1;
            vs      <= 1'b1;
            de      <= 1'b0;
            x       <= 10'd0;
            y       <= 10'd0;
        end else begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 10'd0;
                if (v_count == V_TOTAL - 1)
                    v_count <= 10'd0;
                else
                    v_count <= v_count + 10'd1;
            end else begin
                h_count <= h_count + 10'd1;
            end
            if (h_count >= (H_ACTIVE + H_FRONT) &&
                h_count <  (H_ACTIVE + H_FRONT + H_SYNC))
                hs <= 1'b0;
            else
                hs <= 1'b1;
            if (v_count >= (V_ACTIVE + V_FRONT) &&
                v_count <  (V_ACTIVE + V_FRONT + V_SYNC))
                vs <= 1'b0;
            else
                vs <= 1'b1;
            if (h_count < H_ACTIVE && v_count < V_ACTIVE) begin
                de <= 1'b1;
                x  <= h_count;
                y  <= v_count;
            end else begin
                de <= 1'b0;
                x  <= 10'd0;
                y  <= 10'd0;
            end
        end
    end
endmodule 