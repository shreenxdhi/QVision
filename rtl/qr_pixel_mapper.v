module qr_pixel_mapper #(
    parameter MODULE_SCALE = 6,
    parameter QUIET_ZONE   = 4,
    parameter QR_SIZE      = 21,
    parameter TOTAL_SIZE   = QR_SIZE + 2 * QUIET_ZONE,
    parameter PIXEL_SIZE   = TOTAL_SIZE * MODULE_SCALE,
    parameter X_OFFSET     = (640 - PIXEL_SIZE) / 2,
    parameter Y_OFFSET     = (480 - PIXEL_SIZE) / 2
)(
    input  wire       pix_clk,
    input  wire       rst,
    input  wire       de,
    input  wire [9:0] x,
    input  wire [9:0] y,
    output wire [8:0] fb_addr,
    input  wire       fb_data,
    output reg        pixel_out
);
    wire [9:0] x_next = x + 10'd1;

    wire [9:0] qr_pixel_x = (x_next >= X_OFFSET) ? (x_next - X_OFFSET) : 10'd0;
    wire [9:0] qr_pixel_y = (y      >= Y_OFFSET)  ? (y      - Y_OFFSET) : 10'd0;

    wire [4:0] qr_module_x = qr_pixel_x / MODULE_SCALE;
    wire [4:0] qr_module_y = qr_pixel_y / MODULE_SCALE;

    wire in_qr_area =   (x_next >= X_OFFSET) && (x_next < (X_OFFSET + PIXEL_SIZE)) &&
                        (y      >= Y_OFFSET)  && (y      < (Y_OFFSET + PIXEL_SIZE));

    wire in_quiet_zone = (qr_module_x <  QUIET_ZONE) ||
                         (qr_module_x >= (QUIET_ZONE + QR_SIZE)) ||
                         (qr_module_y <  QUIET_ZONE) ||
                         (qr_module_y >= (QUIET_ZONE + QR_SIZE));

    wire [4:0] fb_module_x = (qr_module_x >= QUIET_ZONE) ? (qr_module_x - QUIET_ZONE) : 5'd0;
    wire [4:0] fb_module_y = (qr_module_y >= QUIET_ZONE) ? (qr_module_y - QUIET_ZONE) : 5'd0;

    assign fb_addr = fb_module_y * QR_SIZE + fb_module_x;

    reg in_qr_area_d, in_quiet_zone_d, de_d;
    always @(posedge pix_clk) begin
        if (rst) begin
            pixel_out       <= 0;
            in_qr_area_d    <= 0;
            in_quiet_zone_d <= 0;
            de_d            <= 0;
        end else begin
            in_qr_area_d    <= in_qr_area;
            in_quiet_zone_d <= in_quiet_zone;
            de_d            <= de;
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
