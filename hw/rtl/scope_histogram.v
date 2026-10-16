`timescale 1ns / 1ps
module scope_histogram
    #(parameter DEPTH = 14400, AW = 14)
    (input wire clk, rst,
     input wire hit,
     input wire [AW - 1 : 0] hit_addr,
     input wire clear, decay,
     input wire [AW - 1 : 0] read_addr,
     output wire [7 : 0] read_data,
     output wire busy,
     output reg [31 : 0] committed = 0, dropped = 0,
     output reg [6 : 0] high_water = 0,
     output wire hit_ready);
    (* ram_style = "block" *) reg [7 : 0] mem[0 : DEPTH - 1];
    reg [AW - 1 : 0] fifo[0 : 63];
    reg [5 : 0] wp = 0, rp = 0;
    reg [6 : 0] count = 0;
    reg scanning = 1, decay_mode = 0, phase = 0;
    reg [AW - 1 : 0] scan_addr = 0;
    wire pop = count != 0 && !scanning;
    wire push = hit && count < 64 && hit_addr < DEPTH;
    reg [7 : 0] q = 0, last_value = 0;
    reg [AW - 1 : 0] a1 = 0, last_addr = 0;
    reg v1 = 0, last_valid = 0;
    wire [7 : 0] old_value = last_valid && a1 == last_addr ? last_value : q;
    wire [7 : 0] new_value = old_value == 255 ? 8'd255 : old_value + 1'b1;
    assign hit_ready = !scanning && count < 63;
    assign busy = scanning || count != 0 || v1;
    assign read_data = q;
    always @(posedge clk)
        if (v1 || (scanning && phase))
            mem[scanning ? scan_addr : a1] <=
                scanning ? (decay_mode ? (q > 0 ? q - 1'b1 : 8'd0) : 8'd0) : new_value;
    always @(posedge clk) begin
        q <= mem[scanning ? scan_addr : pop ? fifo[rp] : read_addr];
        v1 <= pop;
        if (pop) begin
            a1 <= fifo[rp];
            rp <= rp + 1;
        end
        if (push) begin
            fifo[wp] <= hit_addr;
            wp <= wp + 1;
        end
        case ({push, pop})
            2'b10:
                count <= count + 1;
            2'b01:
                count <= count - 1;
            default:
                ;
        endcase
        if (count > high_water)
            high_water <= count;
        if (hit && !push)
            dropped <= dropped + 1;
        last_valid <= v1;
        if (v1) begin
            last_addr <= a1;
            last_value <= new_value;
            committed <= committed + 1;
        end
        if (scanning) begin
            phase <= ~phase;
            if (phase) begin
                if (scan_addr == DEPTH - 1) begin
                    scanning <= 0;
                    scan_addr <= 0;
                end else
                    scan_addr <= scan_addr + 1;
            end
        end else if ((clear || decay) && count == 0 && !v1) begin
            scanning <= 1;
            scan_addr <= 0;
            phase <= 0;
            decay_mode <= decay;
            last_valid <= 0;
        end
        if (rst) begin
            scanning <= 1;
            decay_mode <= 0;
            scan_addr <= 0;
            phase <= 0;
            wp <= 0;
            rp <= 0;
            count <= 0;
            v1 <= 0;
            last_valid <= 0;
            committed <= 0;
            dropped <= 0;
            high_water <= 0;
        end
    end
endmodule
