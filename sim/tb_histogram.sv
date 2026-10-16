`timescale 1ns/1ps
module tb_histogram;
reg clk=0,rst=1;always #5 clk=~clk;reg hit=0,clear=0,decay=0;reg[4:0]addr=7,ra=7;
wire[7:0]data;wire busy;wire[31:0]committed,dropped;wire[6:0]hwm;
scope_histogram #(.DEPTH(32),.AW(5))dut(clk,rst,hit,addr,clear,decay,ra,data,busy,committed,dropped,hwm,);
integer i;reg[31:0]before_count,before_drop;
initial begin repeat(4)@(negedge clk);rst=0;wait(!busy);@(negedge clk);
hit=1;repeat(500)@(negedge clk);hit=0;wait(!busy);repeat(3)@(negedge clk);
if(data!=255||committed!=500||dropped!=0)$fatal(1,"same-address RMW forwarding/saturation %d %d %d",data,committed,dropped);
decay=1;@(negedge clk);decay=0;wait(!busy);repeat(3)@(negedge clk);if(data!=254)$fatal(1,"decay");
clear=1;@(negedge clk);clear=0;wait(!busy);repeat(3)@(negedge clk);if(data!=0)$fatal(1,"clear");
for(i=0;i<32;i++)begin @(negedge clk);addr=i;hit=1;end
@(negedge clk);hit=0;wait(!busy);
for(i=0;i<32;i++)begin ra=i;repeat(3)@(negedge clk);if(data!=1)$fatal(1,"address mapping %d %d",i,data);end
$display("PASS histogram: 500 consecutive same-address hits, saturation, decay, clear, all addresses, zero silent loss");$finish;end
initial begin #100000;$fatal(1,"histogram timeout");end
endmodule
