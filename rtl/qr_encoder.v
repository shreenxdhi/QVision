`timescale 1ns/1ps
`include "qvision_config.vh"
module qr_encoder (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [`LEN_BITS-1:0] payload_length, // already clamped by controller
    input  wire [1:0]  mode,            // 0=byte 1=numeric 2=alnum 3=kanji
    input  wire [4:0]  cnt_w,           // char-count field width (by version)
    input  wire [`LEN_BITS-1:0] data_cw, // total data codewords (capacity)
    input  wire [15:0] payload_bits,
    input  wire [7:0]  buf_rd_data,
    output wire        buf_rd_en,
    output reg  [7:0]  cw_data,
    output reg         cw_valid,
    output reg         done
);
    localparam M_BYTE = 2'd0, M_NUM = 2'd1, M_ALNUM = 2'd2, M_KANJI = 2'd3;

    localparam [3:0] S_IDLE     = 4'd0,
                     S_MODE     = 4'd1,   // 4-bit mode nibble
                     S_COUNT    = 4'd2,   // char-count field
                     S_FETCH    = 4'd3,   // capture one payload byte
                     S_SHIFT    = 4'd4,   // byte mode: serialise 8 bits
                     S_ACC      = 4'd5,   // numeric: accumulate digits
                     S_KANJI_LO = 4'd6,   // kanji: capture the pair's 2nd byte
                     S_EMITS    = 4'd7,   // emit a numeric/alnum/kanji group
                     S_TERM     = 4'd8,   // up to 4 terminator bits
                     S_ALIGN    = 4'd9,   // pad zeros to codeword boundary
                     S_PAD      = 4'd10,  // pad codewords EC / 11
                     S_DONE     = 4'd11,
                     S_PREP     = 4'd12,  // settle capacity accounting
                     S_PROCESS  = 4'd13,  // process registered buffer byte
                     S_KANJI_CALC = 4'd14; // process registered low byte

    reg [3:0]  state;
    reg [1:0]  mode_r;
    reg [3:0]  nibble;        // ISO mode indicator, MSB first
    reg [`LEN_BITS-1:0] len;  // payload length (chars; kanji = bytes, even)
    reg [`LEN_BITS-1:0] data_cw_r;
    reg [4:0]  cnt_w_r;       // count-field width (version-dependent)
    reg [15:0] cnt_bits;      // count field, right-aligned in 16 bits
    reg [4:0]  field_cnt;     // position inside the current field / group
    reg [4:0]  field_len;     // bits in the group being emitted
    reg [2:0]  bit_phase;     // position inside the current codeword (0..7)
    reg [`LEN_BITS-1:0] pay_cnt;  // payload chars consumed
    reg [`LEN_BITS-1:0] cw_idx;   // codewords emitted
    reg [7:0]  byte_acc;
    reg [7:0]  shift_reg;
    reg [7:0]  buf_byte_q;    // timing cut after the prefetched SRAM output
    reg [7:0]  byte_acc_hi;   // kanji: upper byte of the pair
    reg [9:0]  digit_acc;     // numeric group accumulator (0..999)
    reg [5:0]  char_acc;      // alnum char value (0..44)
    reg [12:0] group_val;     // group value, LEFT-aligned (bit 12 first)
    reg [3:0]  term_cnt;      // terminator bits emitted so far
    reg [1:0]  pay3;          // pay_cnt mod 3 (numeric walk counter)
    reg       pad_phase;

    assign buf_rd_en = (state == S_FETCH) || (state == S_KANJI_LO);
    wire in_payload = (state == S_SHIFT) || (state == S_EMITS);
    wire emits_bit = group_val[12 - field_cnt[3:0]];
    wire in_field   = (state == S_MODE)  || (state == S_COUNT) ||
                      (state == S_TERM)  || (state == S_ALIGN);
    wire emitting   = in_payload || in_field;
    wire cw_complete = emitting && (bit_phase == 3'd7);
    wire stream_bit =
        (state == S_MODE)  ? nibble[3 - field_cnt[1:0]] :
        (state == S_COUNT) ? cnt_bits[15 - (field_cnt + (5'd16 - cnt_w_r))] :
        (state == S_SHIFT) ? shift_reg[7 - field_cnt[2:0]] :
                             1'b0;   // S_EMITS uses group_val, handled below
    wire cur_bit    = (state == S_EMITS) ? emits_bit : stream_bit;
    wire [1:0] pay3_n = (pay3 == 2'd2) ? 2'd0 : pay3 + 2'd1;

    reg [3:0] term_len_q;
    reg [15:0] cap_q;
    reg [15:0] pbits_q;

    function [3:0] term_len_q_fn;  // 2-stage variant for the registered
        input [15:0]          cap;
        input [4:0]           cw;
        input [15:0]          pb;
        reg [15:0] used, rem;
        begin
            used = 16'd4 + {10'd0, cw} + pb;
            rem  = cap - used;
            term_len_q_fn = (rem >= 16'd4) ? 4'd4 : rem[3:0];
        end
    endfunction

    function [5:0] alnum_val;    // 0..44
        input [7:0] b;
        begin
            case (b)
                8'h20: alnum_val = 6'd36;  // space
                8'h24: alnum_val = 6'd37;  // $
                8'h25: alnum_val = 6'd38;  // %
                8'h2A: alnum_val = 6'd39;  // *
                8'h2B: alnum_val = 6'd40;  // +
                8'h2D: alnum_val = 6'd41;  // -
                8'h2E: alnum_val = 6'd42;  // .
                8'h2F: alnum_val = 6'd43;  // /
                8'h3A: alnum_val = 6'd44;  // :
                default:
                    alnum_val = (b >= 8'h30 && b <= 8'h39) ? {2'b00, b[3:0]}
                              : ({1'b0, b[4:0]} + 6'd9);   // A-Z -> 10..35
            endcase
        end
    endfunction

    function [12:0] kanji_val;
        input [7:0] hi, lo;
        reg [7:0] h;
        begin
            h = (hi <= 8'h9F) ? (hi - 8'h81) : (hi - 8'hC1);
            kanji_val = h * 13'd192 + {5'b0, lo - 8'h40};
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state      <= S_IDLE;
            cw_valid   <= 1'b0;
            done       <= 1'b0;
            cw_data    <= 8'd0;
            cw_idx     <= 0;
            bit_phase  <= 3'd0;
            byte_acc   <= 8'd0;
            term_cnt   <= 4'd0;
            pay3       <= 2'd0;
            term_len_q <= 4'd0;
            cap_q   <= 0;
            pbits_q <= 16'd0;
            pad_phase <= 1'b0;
        end else begin
            cw_valid <= 1'b0;
            done     <= 1'b0;
            if (cw_complete) begin
                byte_acc  <= {byte_acc[6:0], cur_bit};
                cw_data   <= {byte_acc[6:0], cur_bit};
                cw_valid  <= 1'b1;
                bit_phase <= 3'd0;
                cw_idx    <= cw_idx + 1'b1;
            end else if (emitting) begin
                byte_acc  <= {byte_acc[6:0], cur_bit};
                bit_phase <= bit_phase + 3'd1;
            end

            case (state)
                S_IDLE: begin
                    if (start) begin
                        mode_r    <= mode;
                        len       <= payload_length;
                        data_cw_r <= data_cw;
                        cnt_w_r   <= cnt_w;
                        cnt_bits  <= (mode == M_KANJI)
                                     ? {4'b0, payload_length[`LEN_BITS-1:1]}
                                     : {3'b0, payload_length};
                        nibble    <= (mode == M_NUM)   ? 4'b0001 :
                                     (mode == M_ALNUM) ? 4'b0010 :
                                     (mode == M_KANJI) ? 4'b1000 : 4'b0100;
                        cap_q   <= {data_cw, 3'b000};
                        pbits_q <= payload_bits;
                        field_cnt <= 5'd0;
                        bit_phase <= 3'd0;
                        pay_cnt   <= 0;
                        cw_idx    <= 0;
                        term_cnt  <= 4'd0;
                        digit_acc <= 10'd0;
                        state     <= S_PREP;
                    end
                end

                S_PREP: begin
                    term_len_q <= term_len_q_fn(cap_q, cnt_w_r, pbits_q);
                    state      <= S_MODE;
                end

                S_MODE: begin
                    if (field_cnt == 4'd3) begin
                        field_cnt <= 5'd0;
                        state     <= S_COUNT;
                    end else begin
                        field_cnt <= field_cnt + 5'd1;
                    end
                end

                S_COUNT: begin
                    if (field_cnt == cnt_w_r - 5'd1) begin
                        field_cnt <= 5'd0;
                        state     <= (len == 0) ? S_TERM : S_FETCH;
                    end else begin
                        field_cnt <= field_cnt + 5'd1;
                    end
                end

                S_FETCH: begin
                    field_cnt <= 5'd0;
                    buf_byte_q <= buf_rd_data;
                    state      <= S_PROCESS;
                end

                S_PROCESS: begin
                    if (mode_r == M_BYTE) begin
                        shift_reg <= buf_byte_q;
                        state     <= S_SHIFT;
                    end else if (mode_r == M_NUM) begin
                        digit_acc <= digit_acc * 10'd10 + {6'd0, buf_byte_q[3:0]};
                        pay3      <= pay3_n;
                        if (pay3 == 2'd0)
                            field_len <= (len - pay_cnt >= 3) ? 5'd10 :
                                         (len - pay_cnt == 2) ? 5'd7  : 5'd4;
                        state     <= S_ACC;
                    end else if (mode_r == M_KANJI) begin
                        if (pay_cnt + 1'b1 == len) begin
                            pay_cnt <= pay_cnt + 1'b1;
                            state   <= S_TERM;
                        end else begin
                            byte_acc_hi <= buf_byte_q;   // upper byte
                            pay_cnt     <= pay_cnt + 1'b1;
                            state       <= S_KANJI_LO;
                        end
                    end else begin
                        if (pay_cnt[0] == 1'b0) begin
                            if (pay_cnt + 1'b1 == len) begin
                                group_val <= {7'd0, alnum_val(buf_byte_q)} << 7;
                                field_len <= 5'd6;
                                pay_cnt   <= pay_cnt + 1'b1;
                                state     <= S_EMITS;
                            end else begin
                                char_acc <= alnum_val(buf_byte_q);
                                pay_cnt  <= pay_cnt + 1'b1;
                                state    <= S_FETCH;    // hold for the pair
                            end
                        end else begin
                            group_val <= ((char_acc * 13'd45) +
                                          {7'd0, alnum_val(buf_byte_q)}) << 2;
                            field_len <= 5'd11;
                            pay_cnt   <= pay_cnt + 1'b1;
                            state     <= S_EMITS;
                        end
                    end
                end

                S_KANJI_LO: begin
                    buf_byte_q <= buf_rd_data;
                    state      <= S_KANJI_CALC;
                end

                S_KANJI_CALC: begin
                    group_val <= kanji_val(byte_acc_hi, buf_byte_q);
                    field_len <= 5'd13;
                    pay_cnt   <= pay_cnt + 1'b1;
                    state     <= S_EMITS;
                end

                S_SHIFT: begin
                    if (field_cnt == 4'd7) begin
                        field_cnt <= 5'd0;
                        pay_cnt   <= pay_cnt + 1'b1;
                        state     <= (pay_cnt + 1'b1 == len) ? S_TERM : S_FETCH;
                    end else begin
                        field_cnt <= field_cnt + 5'd1;
                    end
                end

                S_ACC: begin
                    pay_cnt <= pay_cnt + 1'b1;
                    pay3    <= pay3_n;
                    if (pay3_n == 2'd0 || pay_cnt + 1'b1 == len) begin
                        group_val <= {3'b0, digit_acc} << (5'd13 - field_len);
                        state     <= S_EMITS;
                    end else begin
                        state <= S_FETCH;
                    end
                end

                S_EMITS: begin
                    if (field_cnt == field_len - 5'd1) begin
                        field_cnt <= 5'd0;
                        digit_acc <= 10'd0;
                        state     <= (pay_cnt == len) ? S_TERM : S_FETCH;
                    end else begin
                        field_cnt <= field_cnt + 5'd1;
                    end
                end

                S_TERM: begin
                    if (term_len_q == 4'd0 || term_cnt == term_len_q - 4'd1) begin
                        term_cnt <= 4'd0;
                        state    <= S_ALIGN;
                    end else begin
                        term_cnt <= term_cnt + 4'd1;
                    end
                end

                S_ALIGN: begin
                    if (bit_phase == 3'd0) begin
                        pad_phase <= 1'b0;
                        state    <= (cw_idx == data_cw_r) ? S_DONE : S_PAD;
                    end
                end

                S_PAD: begin
                    cw_data  <= pad_phase ? 8'h11 : 8'hEC;
                    cw_valid <= 1'b1;
                    pad_phase <= ~pad_phase;
                    if (cw_idx + 1'b1 == data_cw_r)
                        state <= S_DONE;
                    else
                        cw_idx <= cw_idx + 1'b1;
                end

                S_DONE: begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
