`timescale 1ns / 1ps
module scope_video_timing
    #(parameter H_ACTIVE = 1280, H_FRONT = 110, H_SYNC = 40, H_BACK = 220, V_ACTIVE = 720,
                V_FRONT = 5, V_SYNC = 5, V_BACK = 20)
    (input wire clk, rst,
     output reg [11 : 0] x = 0, y = 0,
     output wire de, hs, vs,
     output wire frame_start);
    localparam HT = H_ACTIVE + H_FRONT + H_SYNC + H_BACK, VT = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;
    always @(posedge clk)
        if (rst) begin
            x <= 0;
            y <= 0;
        end else if (x == HT - 1) begin
            x <= 0;
            if (y == VT - 1)
                y <= 0;
            else
                y <= y + 1;
        end else
            x <= x + 1;
    assign de = x < H_ACTIVE && y < V_ACTIVE;
    assign hs = x >= H_ACTIVE + H_FRONT && x < H_ACTIVE + H_FRONT + H_SYNC;
    assign vs = y >= V_ACTIVE + V_FRONT && y < V_ACTIVE + V_FRONT + V_SYNC;
    assign frame_start = x == 0 && y == V_ACTIVE;
endmodule
