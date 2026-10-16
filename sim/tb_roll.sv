`timescale 1ns/1ps
module tb_roll;
reg clk=0,rst=1;always #5 clk=~clk;reg[11:0]s=100;reg[63:0]idx=0;wire valid;wire[119:0]data;
scope_roll #(.TICKS(16))dut(clk,rst,s,idx,valid,data);
integer i,events=0;
always @(posedge clk)if(!rst)idx<=idx+1;
always @(negedge clk)if(valid)begin events=events+1;if(data[11:0]!=100||data[23:12]!=4095||data[119:88]!=events)$fatal(1,"minmax lost narrow pulse");end
initial begin repeat(4)@(negedge clk);rst=0;
for(i=0;i<160;i++)begin s=i%16==7?4095:100;@(negedge clk);end
@(negedge clk);if(events!=10)$fatal(1,"ROLL bins off by one");$display("PASS roll: narrow pulses preserved in ten full-rate min/max bins");$finish;end
endmodule
