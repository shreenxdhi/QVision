module reset_sync (
    input  wire clk,
    input  wire rst_n,     
    output reg  sync_rst   
);
    reg sync_ff1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_ff1 <= 1'b1;
            sync_rst <= 1'b1;
        end else begin
            sync_ff1 <= 1'b0;
            sync_rst <= sync_ff1;
        end
    end
endmodule
