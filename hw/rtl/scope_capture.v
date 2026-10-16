`timescale 1ns / 1ps
module scope_capture
    #(parameter AW = 14,
      parameter AUTO_TICKS = 1000000)
    (input wire clk, rst,
     input wire[11 : 0] sample,
     input wire otr,
     input wire [31 : 0] config_word,
     input wire cfg_valid,
     input wire release_record,
     output reg [AW - 1 : 0] wr_addr = 0,
     output reg [15 : 0] wr_data = 0,
     output reg wr_en = 0,
     output reg ready = 0,
     output reg [AW - 1 : 0] record_start = 0, trigger_addr = 0,
     output reg [63 : 0] sample_count = 0,
     output reg [31 : 0] otr_count = 0, trigger_count = 0,
     output reg [63 : 0] trigger_index = 0,
     output reg auto_trigger = 0,
     output reg [2 : 0] state = 0,
     output reg [31 : 0] dead_count = 0);
    localparam DEPTH = 1 << AW, PRE = DEPTH / 2;
    localparam IDLE = 0, PREFILL = 1, ARMED = 2, POST = 3, HOLD = 4;
    reg [AW - 1 : 0] addr = 0;
    reg [AW : 0] fill = 0, remaining = 0;
    reg [31 : 0] wait_count = 0, cfg = 32'h1803;
    reg low_seen = 0, high_seen = 0;
    wire run = cfg[0], sim = cfg[1], falling = cfg[2];
    wire [1 : 0] trig_mode = cfg[4 : 3]; // 0 AUTO, 1 NORMAL, 2 SINGLE
    wire [11 : 0] level = cfg[19 : 8];
    wire [7 : 0] hyst = cfg[27 : 20];
    wire [12 : 0] upper_sum = {1'b0, level} + hyst;
    wire [11 : 0] upper = upper_sum > 4095 ? 12'd4095 : upper_sum[11 : 0];
    wire [11 : 0] lower = level < hyst ? 12'd0 : level - hyst;
    wire edge_hit = falling ? (high_seen && sample <= lower) : (low_seen && sample >= upper);
    always @(posedge clk) begin
        wr_en <= 0;
        if (rst) begin
            state <= IDLE;
            addr <= 0;
            fill <= 0;
            remaining <= 0;
            ready <= 0;
            sample_count <= 0;
            otr_count <= 0;
            trigger_count <= 0;
            trigger_index <= 0;
            record_start <= 0;
            trigger_addr <= 0;
            auto_trigger <= 0;
            wait_count <= 0;
            cfg <= 32'h00880003;
            low_seen <= 0;
            high_seen <= 0;
            dead_count <= 0;
        end else begin
            sample_count <= sample_count + 1;
            if (otr)
                otr_count <= otr_count + 1;
            if (cfg_valid) begin
                cfg <= config_word;
                state <= IDLE;
                ready <= 0;
                fill <= 0;
                addr <= 0;
                low_seen <= 0;
                high_seen <= 0;
            end else if (!run) begin
                if (state != HOLD)
                    state <= IDLE;
            end else
                case (state)
                    IDLE: begin
                        state <= PREFILL;
                        fill <= 0;
                        ready <= 0;
                        low_seen <= 0;
                        high_seen <= 0;
                    end
                    PREFILL, ARMED, POST: begin
                        wr_en <= 1;
                        wr_addr <= addr;
                        wr_data <= {3'b0, otr, sample};
                        addr <= addr + 1;
                        if (sample < lower)
                            low_seen <= 1;
                        if (sample > upper)
                            high_seen <= 1;
                        if (state == PREFILL) begin
                            if (fill == PRE - 1) begin
                                state <= ARMED;
                                wait_count <= 0;
                            end else
                                fill <= fill + 1;
                        end
                        if (state == ARMED) begin
                            wait_count <= wait_count + 1;
                            if (edge_hit || (trig_mode == 0 && wait_count == AUTO_TICKS - 1)) begin
                                trigger_addr <= addr;
                                record_start <= addr - PRE;
                                trigger_index <= sample_count;
                                trigger_count <= trigger_count + 1;
                                auto_trigger <= !edge_hit;
                                remaining <= DEPTH - PRE - 1;
                                state <= POST;
                            end
                        end
                        if (state == POST) begin
                            if (remaining == 1) begin
                                state <= HOLD;
                                ready <= 1;
                            end else
                                remaining <= remaining - 1;
                        end
                    end
                    HOLD: begin
                        dead_count <= dead_count + 1;
                        if (release_record && trig_mode != 2) begin
                            ready <= 0;
                            state <= PREFILL;
                            fill <= 0;
                            low_seen <= 0;
                            high_seen <= 0;
                        end
                    end
                    default:
                        state <= IDLE;
                endcase
        end
    end
endmodule
