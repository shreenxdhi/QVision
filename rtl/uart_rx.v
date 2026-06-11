module uart_rx #(
    parameter CLK_HZ = 50000000,
    parameter BAUD = 115200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid,
    output reg        framing_error,
    output reg        overflow,
    input  wire       overflow_clr
);
    localparam CLKS_PER_BIT  = CLK_HZ / BAUD;
    localparam HALF_BIT_TIME = CLKS_PER_BIT / 2;

    localparam IDLE      = 3'b000;
    localparam START_BIT = 3'b001;
    localparam DATA_BITS = 3'b010;
    localparam STOP_BIT  = 3'b011;

    reg [2:0]  state;
    reg [15:0] clk_count;
    reg [2:0]  bit_index;
    reg [7:0]  rx_byte;

    reg rx_ff1, rx_ff2, rx_prev;
    always @(posedge clk) begin
        if (rst) begin
            rx_ff1  <= 1'b1;
            rx_ff2  <= 1'b1;
            rx_prev <= 1'b1;
        end else begin
            rx_ff1  <= rx;
            rx_ff2  <= rx_ff1;
            rx_prev <= rx_ff2;
        end
    end
    wire rx_negedge = rx_prev & ~rx_ff2;

    always @(posedge clk) begin
        if (rst) begin
            state         <= IDLE;
            clk_count     <= 0;
            bit_index     <= 0;
            data          <= 0;
            valid         <= 0;
            framing_error <= 0;
            overflow      <= 0;
            rx_byte       <= 0;
        end else begin
            if (overflow_clr) overflow <= 0;
            valid <= 0;
            
            case (state)
                IDLE: begin
                    clk_count <= 0;
                    bit_index <= 0;
                    if (rx_negedge) begin
                        state <= START_BIT;
                        if (valid) overflow <= 1'b1;
                    end
                end
                START_BIT: begin
                    if (clk_count == HALF_BIT_TIME) begin
                        if (rx_ff2 == 1'b0) begin
                            clk_count <= 0;
                            state     <= DATA_BITS;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                DATA_BITS: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count            <= 0;
                        rx_byte[bit_index]   <= rx_ff2;
                        if (bit_index == 7) begin
                            state <= STOP_BIT;
                        end else begin
                            bit_index <= bit_index + 1;
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                STOP_BIT: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        if (rx_ff2 == 1'b1) begin
                            data          <= rx_byte;
                            valid         <= 1'b1;
                            framing_error <= 1'b0;
                        end else begin
                            framing_error <= 1'b1;
                        end
                        state <= IDLE;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
