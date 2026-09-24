module reset_sync (
    input  wire clk,
    input  wire rst_n,
    (* MAX_FANOUT = 64 *) output reg sync_rst
);
    // Two dedicated metastability-resolution stages followed by a separate
    // reset-distribution register.  The latter may be replicated by synthesis;
    // marking a high-fanout reset output ASYNC_REG prevented that optimization.
    (* ASYNC_REG = "TRUE" *) reg sync_ff1, sync_ff2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_ff1 <= 1'b1;
            sync_ff2 <= 1'b1;
            sync_rst <= 1'b1;
        end else begin
            sync_ff1 <= 1'b0;
            sync_ff2 <= sync_ff1;
            sync_rst <= sync_ff2;
        end
    end
endmodule
