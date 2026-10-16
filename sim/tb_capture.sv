`timescale 1ns/1ps
module tb_capture;
reg clk=0;always #5 clk=~clk;
reg rst=1,otr=0,cv=0,rel=0;reg[11:0] sample=100;reg[31:0] cfg;
wire[3:0] wa,rs,ta;wire[15:0] wd;wire we,ready,aut;
wire[63:0] count,ti;wire[31:0] oc,tc,dead;wire[2:0] state;
scope_capture #(.AW(4),.AUTO_TICKS(32)) dut(clk,rst,sample,otr,cfg,cv,rel,wa,wd,we,ready,rs,ta,count,oc,tc,ti,aut,state,dead);
reg[15:0] mem[0:15];reg[63:0] indices[0:15];integer writes=0,i,trigger_time;
always @(posedge clk)if(we)begin mem[wa]<=wd;indices[wa]<=count-1;writes<=writes+1;end
task tick(input[11:0] s,input o);begin @(negedge clk);sample=s;otr=o;@(posedge clk);#1;end endtask
task configure(input[31:0] c);begin @(negedge clk);cfg=c;cv=1;@(negedge clk);cv=0;end endtask
task reset;begin rst=1;repeat(5)@(negedge clk);rst=0;end endtask
initial begin
 reset();configure(32'h0088000b); // Normal, rising, level 0x800, hysteresis 8.
 repeat(45)tick(100,0); // wrap several times before trigger.
 tick(2047,0);tick(2050,0);
 if(tc!=0)$fatal(1,"hysteresis fired early");
 tick(3000,1);trigger_time=ti;
 wait(ready);repeat(3)@(negedge clk);
 if(tc!=1||aut)$fatal(1,"Normal edge count/auto");
 if(mem[(ta)&15]!==16'h1bb8)$fatal(1,"trigger sample and OTR not aligned");
 if(rs!==((ta-8)&15))$fatal(1,"pretrigger record start");
 for(i=0;i<16;i=i+1)if(indices[(rs+i)&15]!==ti-8+i)$fatal(1,"chronological ordering/off-by-one idx=%0d got=%0d expect=%0d",i,indices[(rs+i)&15],ti-8+i);
 i=writes;repeat(20)tick(100,0);if(writes!=i)$fatal(1,"writes continued during HOLD");
 rel=1;tick(100,0);rel=0;repeat(12)tick(100,0);if(state!=2)$fatal(1,"Normal rearm");
 configure(32'h00880017); // Single falling.
 repeat(12)tick(3000,0);tick(100,0);wait(ready);repeat(3)@(negedge clk);
 rel=1;repeat(20)tick(3000,0);rel=0;if(!ready||state!=4)$fatal(1,"Single rearmed");
 configure(32'h00880003);repeat(80)tick(100,0);
 if(!ready||!aut)$fatal(1,"AUTO timeout failed");
 configure(32'h00880002);repeat(10)tick(100,0);if(state!=0)$fatal(1,"STOP did not stop");
 $display("PASS capture: wrap, hysteresis, OTR, exact pre/post, HOLD, Single, Auto, STOP");$finish;
end
initial begin #100000;$fatal(1,"capture timeout");end
endmodule
