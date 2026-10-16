`timescale 1ns / 1ps
module reset_sync
    (input wire clk,
     input wire arst,
     output wire rst);
    (* ASYNC_REG = "TRUE" *) reg [3 : 0] pipe = 4'hf;
    always @(posedge clk or posedge arst)
        if (arst)
            pipe <= 4'hf;
        else
            pipe <= {pipe[2 : 0], 1'b0};
    assign rst = pipe[3];
endmodule
// A bundled-data mailbox: data stays stable from request until acknowledgement.
// Each side must see a common reset assertion. No per-bit data synchronizers.
module scope_mailbox
    #(parameter WIDTH = 32)
    (input wire sclk, srst,
     input wire [WIDTH - 1 : 0] sdata,
     input wire send,
     output wire busy,
     input wire dclk, drst,
     output reg [WIDTH - 1 : 0] ddata,
     output reg valid);
    reg [WIDTH - 1 : 0] hold_data = 0;
    reg req = 0, ack = 0;
    (* ASYNC_REG = "TRUE" *) reg ack_meta = 0, ack_sync = 0, req_meta = 0, req_sync = 0;
    assign busy = req != ack_sync;
    always @(posedge sclk)
        if (srst) begin
            req <= 0;
            ack_meta <= 0;
            ack_sync <= 0;
            hold_data <= 0;
        end else begin
            ack_meta <= ack;
            ack_sync <= ack_meta;
            if (send && !busy) begin
                hold_data <= sdata;
                req <= ~req;
            end
        end
    always @(posedge dclk)
        if (drst) begin
            req_meta <= 0;
            req_sync <= 0;
            ack <= 0;
            ddata <= 0;
            valid <= 0;
        end else begin
            req_meta <= req;
            req_sync <= req_meta;
            valid <= 0;
            if (req_sync != ack) begin
                ddata <= hold_data;
                valid <= 1;
                ack <= req_sync;
            end
        end
endmodule
