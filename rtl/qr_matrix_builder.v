`timescale 1ns/1ps
module qr_matrix_builder (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire [7:0] codeword_data,
    input  wire       codeword_valid,
    output reg  [8:0] fb_addr,     
    output reg        fb_din,      
    output reg        fb_we,       
    output reg        done
);
    parameter QR_SIZE = 21;
    parameter TOTAL_BYTES = 36;      
    localparam IDLE           = 4'd0;
    localparam DRAW_FINDERS   = 4'd1;
    localparam DRAW_TIMING    = 4'd2;
    localparam DRAW_DARK      = 4'd3;
    localparam PLACE_DATA     = 4'd4;
    localparam FINISH         = 4'd5;
    reg [3:0] state;
    reg [7:0] codewords [0:TOTAL_BYTES-1];
    reg [5:0] cw_count;
    reg       collecting;
    reg [6:0] finder_pattern [0:6];
    initial begin
        finder_pattern[0] = 7'b1111111;  
        finder_pattern[1] = 7'b1000001;  
        finder_pattern[2] = 7'b1011101;
        finder_pattern[3] = 7'b1011101;  
        finder_pattern[4] = 7'b1011101;
        finder_pattern[5] = 7'b1000001;
        finder_pattern[6] = 7'b1111111;
    end
    reg [2:0] fp_x, fp_y;
    reg [1:0] fp_idx;
    reg [3:0] t_idx;
    reg       timing_phase;
    reg [4:0] base_x, base_y;
    reg [4:0] cur_x, cur_y;
    reg [8:0] data_bit_idx;
    reg [8:0] pixel_idx;
    reg [4:0] data_x, data_y;
    wire [5:0] c_byte_idx;
    wire [2:0] c_bit_pos;
    wire       c_data_bit;
    wire       c_mask_bit;
    wire [7:0] c_selected_byte;
    assign c_byte_idx = data_bit_idx[8:3];
    assign c_bit_pos = 3'd7 - data_bit_idx[2:0];
    assign c_selected_byte = codewords[c_byte_idx];
    assign c_data_bit = c_selected_byte[c_bit_pos];
    assign c_mask_bit = ((data_y[0] ^ data_x[0]) == 1'b0) ? 1'b1 : 1'b0;
    always @(*) begin
        fb_addr = cur_y * QR_SIZE + cur_x;
    end
    integer i;
    initial begin
        for (i = 0; i < TOTAL_BYTES; i = i + 1)
            codewords[i] = 8'h00;
    end
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            fp_x <= 0; fp_y <= 0; fp_idx <= 0;
            t_idx <= 0; timing_phase <= 0;
            base_x <= 0; base_y <= 0;
            cur_x <= 0; cur_y <= 0;
            fb_din <= 0; fb_we <= 0;
            done <= 0;
            cw_count <= 0;
            collecting <= 0;
            data_bit_idx <= 0;
            pixel_idx <= 0;
            data_x <= 0;
            data_y <= 0;
        end else begin
            fb_we <= 0;
            done <= 0;
            if (collecting && codeword_valid) begin
                if (cw_count < TOTAL_BYTES) begin
                    codewords[cw_count] <= codeword_data;
                    cw_count <= cw_count + 1;
                end
            end
            case (state)
                IDLE: begin
                    if (start) begin
                        cw_count <= 0;
                        collecting <= 1;
                        fp_idx <= 0;
                        fp_x <= 0;
                        fp_y <= 0;
                        state <= DRAW_FINDERS;
                    end
                end
                DRAW_FINDERS: begin
                    case (fp_idx)
                        2'd0: begin cur_x <= {2'b0, fp_x};       cur_y <= {2'b0, fp_y};       end
                        2'd1: begin cur_x <= 5'd14 + {2'b0, fp_x}; cur_y <= {2'b0, fp_y};       end
                        2'd2: begin cur_x <= {2'b0, fp_x};       cur_y <= 5'd14 + {2'b0, fp_y}; end
                        default: begin cur_x <= 0; cur_y <= 0; end
                    endcase
                    fb_din <= finder_pattern[fp_y][3'd6 - fp_x];
                    fb_we <= 1;
                    if (fp_x == 3'd6) begin
                        fp_x <= 0;
                        if (fp_y == 3'd6) begin
                            fp_y <= 0;
                            if (fp_idx == 2'd2) begin
                                state <= DRAW_TIMING;
                                timing_phase <= 0;
                                t_idx <= 0;
                            end else begin
                                fp_idx <= fp_idx + 1;
                            end
                        end else begin
                            fp_y <= fp_y + 1;
                        end
                    end else begin
                        fp_x <= fp_x + 1;
                    end
                end
                DRAW_TIMING: begin
                    fb_we <= 1;
                    if (timing_phase == 1'b0) begin
                        cur_x <= 5'd8 + {1'b0, t_idx};
                        cur_y <= 5'd6;
                        fb_din <= ~t_idx[0];
                        if (t_idx == 4'd4) begin
                            timing_phase <= 1;
                            t_idx <= 0;
                        end else begin
                            t_idx <= t_idx + 1;
                        end
                    end else begin
                        cur_x <= 5'd6;
                        cur_y <= 5'd8 + {1'b0, t_idx};
                        fb_din <= ~t_idx[0];
                        if (t_idx == 4'd4) begin
                            state <= DRAW_DARK;
                        end else begin
                            t_idx <= t_idx + 1;
                        end
                    end
                end
                DRAW_DARK: begin
                    cur_x <= 5'd8;
                    cur_y <= 5'd13;
                    fb_din <= 1;
                    fb_we <= 1;
                    state <= PLACE_DATA;
                    data_bit_idx <= 0;
                    pixel_idx <= 0;
                    data_x <= 5'd9;
                    data_y <= 5'd9;
                    collecting <= 0;
                end
                PLACE_DATA: begin
                    if (data_bit_idx < 9'd288 && data_y < 5'd21) begin
                        cur_x <= data_x;
                        cur_y <= data_y;
                        fb_din <= c_data_bit ^ c_mask_bit;
                        fb_we <= 1;
                        data_bit_idx <= data_bit_idx + 1;
                        if (data_x == 5'd20) begin
                            data_x <= 5'd9;
                            if (data_y == 5'd12) begin
                                data_y <= 5'd14;
                            end else begin
                                data_y <= data_y + 1;
                            end
                        end else begin
                            data_x <= data_x + 1;
                        end
                    end else begin
                        state <= FINISH;
                    end
                end
                FINISH: begin
                    done <= 1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
