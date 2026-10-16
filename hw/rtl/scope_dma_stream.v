`timescale 1ns / 1ps
module scope_dma_stream
    (input wire adc_clk, adc_rst,
     input wire[15 : 0] sample,
     input wire start,
     input wire [31 : 0] count,
     input wire bus_clk, bus_rst,
     output wire [15 : 0] m_axis_tdata,
     output wire [1 : 0] m_axis_tkeep,
     output wire m_axis_tvalid,
     input wire m_axis_tready,
     output wire m_axis_tlast,
     output reg [31 : 0] dropped = 0, produced = 0,
     output reg active = 0,
     output wire [12 : 0] fifo_level,
     input wire flush,
     input wire [63 : 0] sample_index,
     output reg [63 : 0] first_index = 0);

    reg reset_request = 1;
    always @(posedge bus_clk)
        reset_request <= bus_rst | flush;
    (* ASYNC_REG = "TRUE" *) reg [7 : 0] reset_pipe = 8'hff;
    always @(posedge adc_clk or posedge reset_request)
        if (reset_request)
            reset_pipe <= 8'hff;
        else
            reset_pipe <= {reset_pipe[6 : 0], 1'b0};
    wire local_reset = reset_pipe[7] | adc_rst;
    wire [31 : 0] command;
    wire command_valid, command_busy;
    scope_mailbox #(.WIDTH(32))
        cmd(.sclk(bus_clk),
            .srst(bus_rst | flush),
            .sdata(count),
            .send(start),
            .busy(command_busy),
            .dclk(adc_clk),
            .drst(local_reset),
            .ddata(command),
            .valid(command_valid));
    reg [31 : 0] remaining = 0;
    wire full, empty, wr_busy, rd_busy;
    wire [16 : 0] dout;
    wire write_en = active && !full && !wr_busy;
    always @(posedge adc_clk) begin
        if (adc_rst) begin
            remaining <= 0;
            active <= 0;
            dropped <= 0;
            produced <= 0;
            first_index <= 0;
        end else if (local_reset) begin
            remaining <= 0;
            active <= 0;
        end else begin
            if (command_valid && !active && command != 0) begin
                remaining <= command;
                active <= 1;
                first_index <= sample_index + 1;
            end
            if (active) begin
                if (full || wr_busy) begin
                    dropped <= dropped + remaining;
                    remaining <= 0;
                    active <= 0;
                end else begin
                    produced <= produced + 1;
                    remaining <= remaining - 1;
                    if (remaining == 1)
                        active <= 0;
                end
            end
        end
    end
    xpm_fifo_async #(.FIFO_MEMORY_TYPE("block"),
                     .FIFO_WRITE_DEPTH(4096),
                     .WRITE_DATA_WIDTH(17),
                     .READ_DATA_WIDTH(17),
                     .READ_MODE("fwft"),
                     .FIFO_READ_LATENCY(0),
                     .CDC_SYNC_STAGES(2),
                     .DOUT_RESET_VALUE("0"),
                     .WR_DATA_COUNT_WIDTH(13),
                     .RD_DATA_COUNT_WIDTH(13),
                     .USE_ADV_FEATURES("0707"))
        sample_fifo(.rst(local_reset),
                    .wr_clk(adc_clk),
                    .wr_en(write_en),
                    .din({remaining == 1, sample}),
                    .full(full),
                    .wr_rst_busy(wr_busy),
                    .wr_data_count(),
                    .prog_full(),
                    .almost_full(),
                    .overflow(),
                    .wr_ack(),
                    .rd_clk(bus_clk),
                    .rd_en(m_axis_tready && !empty && !rd_busy),
                    .dout(dout),
                    .empty(empty),
                    .rd_rst_busy(rd_busy),
                    .rd_data_count(fifo_level),
                    .prog_empty(),
                    .almost_empty(),
                    .underflow(),
                    .data_valid(),
                    .sleep(1'b0),
                    .injectsbiterr(1'b0),
                    .injectdbiterr(1'b0),
                    .sbiterr(),
                    .dbiterr());
    assign m_axis_tdata = dout[15 : 0];
    assign m_axis_tlast = dout[16];
    assign m_axis_tkeep = 2'b11;
    assign m_axis_tvalid = !empty && !rd_busy;
endmodule
