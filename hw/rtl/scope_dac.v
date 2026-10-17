`timescale 1ns/1ps
// DAC-only DDS. Fixed 50 MSa/s clock; no ADC signals enter this module.
// Inactive table bank is immutable during a commit handshake. Configuration
// is captured atomically; the old output continues during table uploads.
module scope_dac(
 input wire sys_clk, sys_rst, dac_clock,
 input wire table_we, input wire [10:0] table_addr, input wire [13:0] table_data,
 input wire [10:0] read_addr, output reg [13:0] read_data=0,
 input wire commit, input wire [31:0] phase_step,
 input wire enable, input wire [13:0] idle_code,
 output wire busy, output wire active_bank,
 output wire [79:0] status, output wire [13:0] dac_data);
 (* ram_style="block" *) reg [13:0] table_mem[0:4095];
 reg bank_sys=0;
 wire valid, dac_rst;
 reg dac_reset_sync=1;
 wire [47:0] config_dac;
 reset_sync dr(.clk(dac_clock),.arst(sys_rst),.rst(dac_rst));
 // A clocked reset for the data-path flops also ensures that power-optimized
 // BRAM read enables cannot be driven by an asynchronously asserted reset.
 always @(posedge dac_clock) dac_reset_sync<=dac_rst;
 scope_mailbox #(.WIDTH(48)) cfg(
 .sclk(sys_clk),.srst(sys_rst),.sdata({bank_sys,enable,idle_code,phase_step}),
 .send(commit && !busy),.busy(busy),.dclk(dac_clock),.drst(dac_rst),
 .ddata(config_dac),.valid(valid));
 // The system port MUST use one shared address for read/write. Independent
 // read and write addresses would infer a three-port LUTRAM and create an
 // unnecessary asynchronous write-data path into the DAC reader.
 wire [10:0] sys_address=table_we ? table_addr : read_addr;
 always @(posedge sys_clk) begin
   read_data <= table_mem[{bank_sys,sys_address}];
   if (sys_rst) bank_sys<=0;
   else begin
     if(table_we && !busy) table_mem[{bank_sys,sys_address}]<=table_data;
     if(commit && !busy) bank_sys<=~bank_sys;
   end
 end
 // Sys-side bank is the next upload bank; ACK confirms the active bank.
 assign active_bank=~bank_sys;
 reg [31:0] phase=0, step=0, cycles=0;
 reg enabled=0, bank=0;
 reg [13:0] idle=8192, lookup;
 always @(posedge dac_clock) lookup<=table_mem[{bank,phase[31:21]}];
 reg enabled_q=0;
 reg [13:0] idle_q=8192;
 always @(posedge dac_clock) begin
   if(dac_reset_sync) begin
     phase<=0;step<=0;enabled<=0;bank<=0;idle<=8192;
     enabled_q<=0;idle_q<=8192;cycles<=0;
   end else begin
     cycles<=cycles+1;
     enabled_q<=enabled; idle_q<=idle;
     phase<=phase+step;
     if(valid) begin
       bank<=config_dac[47]; enabled<=config_dac[46];
       idle<=config_dac[45:32];step<=config_dac[31:0];phase<=0;
     end
   end
 end
 // Change the physical pins on FALLING edges. DAC904 latches RISING edges.
 (* IOB="TRUE" *) reg [13:0] output_q=8192;
 always @(negedge dac_clock) output_q<=enabled_q ? lookup : idle_q;
 assign dac_data=output_q;
 wire status_busy,status_valid;
 scope_mailbox #(.WIDTH(80)) monitor(.sclk(dac_clock),.srst(dac_rst),
 .sdata({phase,output_q,enabled,bank,cycles}),.send(!status_busy),.busy(status_busy),
 .dclk(sys_clk),.drst(sys_rst),.ddata(status),.valid(status_valid));
endmodule
