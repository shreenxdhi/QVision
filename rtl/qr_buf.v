module qr_buf (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] in_byte,
    input  wire       in_valid,
    input  wire       commit,
    input  wire       clear,
    output wire [7:0] rd_data,
    input  wire       rd_en,
    output wire [7:0] length,
    output reg        committed_flag
);
    parameter BUF_SIZE = 32;
    parameter ADDR_BITS = 5;
    reg [7:0] buffer [0:BUF_SIZE-1];
    reg [ADDR_BITS:0] wr_ptr;    
    reg [ADDR_BITS:0] rd_ptr;
    reg [ADDR_BITS:0] committed_length;  
    wire [ADDR_BITS-1:0] wr_addr = wr_ptr[ADDR_BITS-1:0];
    wire [ADDR_BITS-1:0] rd_addr = rd_ptr[ADDR_BITS-1:0];
    wire [ADDR_BITS:0] current_length;
    assign current_length = (wr_ptr >= rd_ptr) ? (wr_ptr - rd_ptr) : (BUF_SIZE - rd_ptr + wr_ptr);
    assign length = committed_flag ? {2'b00, committed_length[5:0]} : {2'b00, current_length[5:0]};
    assign rd_data = buffer[rd_addr];
    always @(posedge clk) begin
        if (rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            committed_flag <= 0;
            committed_length <= 0;
        end else begin
            if (clear) begin
                wr_ptr <= 0;
                rd_ptr <= 0;
                committed_flag <= 0;
                committed_length <= 0;
            end
            else if (commit && !committed_flag) begin
                committed_flag <= 1;
                committed_length <= wr_ptr[ADDR_BITS:0];
            end
            else if (in_valid && !committed_flag) begin
                buffer[wr_addr] <= in_byte;
                wr_ptr <= wr_ptr + 1;
            end
            if (rd_en && (rd_ptr != wr_ptr)) begin
                rd_ptr <= rd_ptr + 1;
            end
        end
    end
endmodule
