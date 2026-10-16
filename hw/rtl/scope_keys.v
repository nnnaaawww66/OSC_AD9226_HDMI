`timescale 1ns / 1ps
module scope_keys
    #(parameter DEBOUNCE = 1000000, LONG_TICKS = 70000000)
    (input wire clk, rst,
     input wire [1 : 0] key_n,
     output reg [31 : 0] event_word = 0);
    (* ASYNC_REG = "TRUE" *) reg [1 : 0] meta = 3, sync = 3;
    reg [1 : 0] stable = 0, candidate = 0, gesture = 0;
    reg [31 : 0] debounce = 0, duration = 0;
    reg long_sent = 0;
    reg [15 : 0] seq = 0;
    reg [11 : 0] duration_ms = 0;
    reg [16 : 0] ms_ticks = 0;
    always @(posedge clk) begin
        meta <= key_n;
        sync <= meta;
        if (rst) begin
            stable <= 0;
            candidate <= 0;
            gesture <= 0;
            debounce <= 0;
            duration <= 0;
            duration_ms <= 0;
            ms_ticks <= 0;
            long_sent <= 0;
            seq <= 0;
            event_word <= 0;
        end else begin
            if (~sync != candidate) begin
                candidate <= ~sync;
                debounce <= 0;
            end else if (debounce < DEBOUNCE)
                debounce <= debounce + 1;
            else
                stable <= candidate;
            if (stable != 0) begin
                if (ms_ticks == 99999) begin
                    ms_ticks <= 0;
                    if (duration_ms != 4095)
                        duration_ms <= duration_ms + 1;
                end else
                    ms_ticks <= ms_ticks + 1;
                gesture <= gesture | stable;
                if (duration < LONG_TICKS)
                    duration <= duration + 1;
                else if (!long_sent) begin
                    seq <= seq + 1;
                    event_word <= {seq + 16'd1, duration_ms, 1'b0, 1'b1, gesture | stable};
                    long_sent <= 1;
                end
            end else if (gesture != 0) begin
                if (!long_sent) begin
                    seq <= seq + 1;
                    event_word <= {seq + 16'd1, duration_ms, 1'b0, 1'b0, gesture};
                end
                duration <= 0;
                duration_ms <= 0;
                ms_ticks <= 0;
                gesture <= 0;
                long_sent <= 0;
            end
        end
    end
endmodule
