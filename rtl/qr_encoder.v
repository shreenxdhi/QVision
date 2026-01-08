module qr_encoder (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire [7:0] payload_length,
    input  wire [7:0] buf_rd_data,
    output reg        buf_rd_en,
    output reg  [7:0] codeword_data,
    output reg        codeword_valid,
    output reg        done
);
    parameter TOTAL_CODEWORDS = 26;  
    parameter PAD_BYTE_1 = 8'hEC;
    parameter PAD_BYTE_2 = 8'h11;
    parameter IDLE        = 4'b0000;
    parameter MODE        = 4'b0001;
    parameter LENGTH      = 4'b0010;
    parameter PAYLOAD     = 4'b0011;
    parameter TERMINATOR  = 4'b0100;
    parameter PADDING     = 4'b0101;
    parameter DONE_ST     = 4'b0110;
    reg [3:0] state;
    reg [7:0] byte_count;
    reg [7:0] payload_count;
    reg pad_toggle;  
    reg [7:0] stored_payload_length;
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            byte_count <= 0;
            payload_count <= 0;
            pad_toggle <= 0;
            codeword_data <= 0;
            codeword_valid <= 0;
            buf_rd_en <= 0;
            done <= 0;
            stored_payload_length <= 0;
        end else begin
            codeword_valid <= 0;  
            buf_rd_en <= 0;
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= MODE;
                        byte_count <= 0;
                        payload_count <= 0;
                        pad_toggle <= 0;
                        done <= 0;
                        stored_payload_length <= payload_length;
                    end
                end
                MODE: begin
                    codeword_data <= 8'h04;  
                    codeword_valid <= 1;
                    byte_count <= byte_count + 1;
                    state <= LENGTH;
                end
                LENGTH: begin
                    codeword_data <= stored_payload_length;
                    codeword_valid <= 1;
                    byte_count <= byte_count + 1;
                    if (stored_payload_length > 0) begin
                        state <= PAYLOAD;
                        buf_rd_en <= 1;  
                    end else begin
                        state <= TERMINATOR;
                    end
                end
                PAYLOAD: begin
                    codeword_data <= buf_rd_data;
                    codeword_valid <= 1;
                    byte_count <= byte_count + 1;
                    payload_count <= payload_count + 1;
                    if (payload_count == stored_payload_length - 1) begin
                        state <= TERMINATOR;
                    end else begin
                        buf_rd_en <= 1;  
                    end
                end
                TERMINATOR: begin
                    if (byte_count < TOTAL_CODEWORDS) begin
                        codeword_data <= 8'h00;  
                        codeword_valid <= 1;
                        byte_count <= byte_count + 1;
                    end
                    if (byte_count < TOTAL_CODEWORDS - 1) begin
                        state <= PADDING;
                    end else begin
                        state <= DONE_ST;
                    end
                end
                PADDING: begin
                    if (byte_count < TOTAL_CODEWORDS) begin
                        codeword_data <= pad_toggle ? PAD_BYTE_2 : PAD_BYTE_1;
                        codeword_valid <= 1;
                        byte_count <= byte_count + 1;
                        pad_toggle <= ~pad_toggle;
                    end
                    if (byte_count >= TOTAL_CODEWORDS - 1) begin
                        state <= DONE_ST;
                    end
                end
                DONE_ST: begin
                    done <= 1;
                    if (start) begin
                        state <= IDLE;
                        done <= 0;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
