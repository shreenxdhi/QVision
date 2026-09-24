`timescale 1ns/1ps
`include "qvision_config.vh"
module qr_pixel_mapper #(
    parameter QUIET_ZONE   = 4,
    parameter SCR_W        = 640,
    parameter SCR_H        = 480
)(
    input  wire       pix_clk,
    input  wire       rst,
    input  wire       de,
    input  wire [9:0] x,
    input  wire [9:0] y,
    input  wire [7:0] qr_size,       // 21 / 25 / ... / 177 (current symbol)
    output wire [`FB_ADDR_BITS-1:0] fb_addr,
    input  wire       fb_data,
    output reg        pixel_out
);
    // 2-stage synchronizer for the qr_size clock-domain crossing
    (* ASYNC_REG = "TRUE" *) reg [7:0] qr_size_q1, qr_size_q2;
    wire [7:0] qr_size_sync = qr_size_q2;
    // per-size power-of-two scale so every version fills the screen and
    // module division stays a shift (8x / 4x / 2x by size); the quiet
    // zone is preserved at every scale
    wire [7:0] total_modules = qr_size_sync + 2 * QUIET_ZONE;
    wire [2:0] scale_shift   = (qr_size_sync <= 8'd49) ? 3'd3 :
                               (qr_size_sync <= 8'd93) ? 3'd2 : 3'd1;
    wire [10:0] pixel_size   = total_modules << scale_shift;
    wire [10:0] x_offset     = (SCR_W - pixel_size) >> 1;
    wire [10:0] y_offset     = (SCR_H - pixel_size) >> 1;

    // fb_addr is presented one cycle ahead of the gating signals so that the
    // synchronous BRAM read returns fb_data exactly when the pipeline
    // registers (in_qr_area_d / de_d) select it - no pixel shift.
    wire [9:0] qr_pixel_x = (x >= x_offset[9:0]) ? (x - x_offset[9:0]) : 10'd0;
    wire [9:0] qr_pixel_y = (y >= y_offset[9:0]) ? (y - y_offset[9:0]) : 10'd0;

    wire [7:0] qr_module_x = qr_pixel_x >> scale_shift;
    wire [7:0] qr_module_y = qr_pixel_y >> scale_shift;

    wire [10:0] x_rel = x - x_offset[9:0];
    wire [10:0] y_rel = y - y_offset[9:0];
    wire in_qr_area = (x >= x_offset[9:0]) && (x_rel < pixel_size) &&
                      (y >= y_offset[9:0]) && (y_rel < pixel_size);

    wire in_quiet_zone = (qr_module_x <  QUIET_ZONE) ||
                         (qr_module_x >= (QUIET_ZONE + qr_size_sync)) ||
                         (qr_module_y <  QUIET_ZONE) ||
                         (qr_module_y >= (QUIET_ZONE + qr_size_sync));

    wire [7:0] fb_module_x = (qr_module_x >= QUIET_ZONE) ? (qr_module_x - QUIET_ZONE) : 8'd0;
    wire [7:0] fb_module_y = (qr_module_y >= QUIET_ZONE) ? (qr_module_y - QUIET_ZONE) : 8'd0;

    assign fb_addr = fb_module_y * qr_size_sync + fb_module_x;

    reg in_qr_area_d, in_quiet_zone_d, de_d;
    always @(posedge pix_clk) begin
        if (rst) begin
            pixel_out       <= 0;
            in_qr_area_d    <= 0;
            in_quiet_zone_d <= 0;
            de_d            <= 0;
            qr_size_q1      <= 8'd0;
            qr_size_q2      <= 8'd0;
        end else begin
            in_qr_area_d    <= in_qr_area;
            in_quiet_zone_d <= in_quiet_zone;
            de_d            <= de;
            qr_size_q1      <= qr_size;
            qr_size_q2      <= qr_size_q1;
            if (de_d) begin
                if (in_qr_area_d) begin
                    if (in_quiet_zone_d) begin
                        pixel_out <= 0;
                    end else begin
                        pixel_out <= fb_data;
                    end
                end else begin
                    pixel_out <= 0;
                end
            end else begin
                pixel_out <= 0;
            end
        end
    end
endmodule
