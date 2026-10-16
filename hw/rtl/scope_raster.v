`timescale 1ns / 1ps
// Bounded Bresenham rasterizer shared by DPX and EYE. Exactly one hit per ready cycle.
// Previous endpoint is excluded from the next segment. A wrap/jump starts a new point.
module scope_raster
    (input wire clk, rst, clear,
     input wire point_valid,
     input wire [7 : 0] point_x,
     input wire [6 : 0] point_y,
     input wire hit_ready,
     output wire hit_valid,
     output wire [13 : 0] hit_address,
     output wire busy,
     output reg [31 : 0] point_drops = 0);
    reg [1 : 0] state = 0;
    reg previous_valid = 0;
    reg [7 : 0] prev_x = 0, x = 0, goal_x = 0;
    reg [6 : 0] prev_y = 0, y = 0, goal_y = 0;
    reg signed [10 : 0] dx = 0, dy = 0, err = 0;
    reg sx = 0, sy = 0;
    wire [7 : 0] dx_abs = point_x >= prev_x ? point_x - prev_x : prev_x - point_x;
    wire [6 : 0] dy_abs = point_y >= prev_y ? point_y - prev_y : prev_y - point_y;
    wire signed [10 : 0] twice_err = err <<< 1;
    wire step_x = twice_err >= dy, step_y = twice_err <= dx;
    wire signed [10 : 0] next_err = err + (step_x ? dy : 11'sd0) + (step_y ? dx : 11'sd0);
    wire [7 : 0] next_x = step_x ? (sx ? x + 1'b1 : x - 1'b1) : x;
    wire [6 : 0] next_y = step_y ? (sy ? y + 1'b1 : y - 1'b1) : y;
    assign busy = state != 0;
    assign hit_valid = state == 2;
    assign hit_address = y * 160 + x;
    always @(posedge clk) begin
        if (rst) begin
            state <= 0;
            previous_valid <= 0;
            point_drops <= 0;
        end else begin
            if (clear && state == 0)
                previous_valid <= 0;
            if (point_valid) begin
                if (state != 0 || point_x >= 160 || point_y >= 90)
                    point_drops <= point_drops + 1;
                else begin
                    prev_x <= point_x;
                    prev_y <= point_y;
                    previous_valid <= 1;
                    goal_x <= point_x;
                    goal_y <= point_y;
                    if (!previous_valid || point_x < prev_x || dx_abs > 80 ||
                        (point_x == prev_x && point_y == prev_y)) begin
                        x <= point_x;
                        y <= point_y;
                        state <= 2;
                    end else begin
                        x <= prev_x;
                        y <= prev_y;
                        dx <= $signed({3'b0, dx_abs});
                        dy <= -$signed({4'b0, dy_abs});
                        err <= $signed({3'b0, dx_abs}) - $signed({4'b0, dy_abs});
                        sx <= point_x >= prev_x;
                        sy <= point_y >= prev_y;
                        state <= 1;
                    end
                end
            end
            if (state == 1) begin
                x <= next_x;
                y <= next_y;
                err <= next_err;
                state <= 2;
            end
            if (state == 2 && hit_ready) begin
                if (x == goal_x && y == goal_y)
                    state <= 0;
                else begin
                    x <= next_x;
                    y <= next_y;
                    err <= next_err;
                end
            end
        end
    end
endmodule
