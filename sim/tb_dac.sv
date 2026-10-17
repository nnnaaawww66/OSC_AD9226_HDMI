`timescale 1ns/1ps
module tb_dac;
reg sc=0,dc=0,rst=1,we=0,commit=0,on=0;
always #5 sc=~sc;
always #10 dc=~dc;
reg[10:0] addr=0,ra=0;
reg[13:0] value=0,idle=8192;
reg[31:0] step=32'h00200000;
wire[13:0] data,read_data;
wire busy,bank;wire[79:0] status;
scope_dac dut(sc,rst,dc,we,addr,value,ra,read_data,commit,step,on,idle,busy,bank,status,data);
integer i,expected,checked=0;reg check=0;time last_change=0;
always @(data)last_change=$time;
always @(posedge dc)if(check)begin
 if($time-last_change<9)$fatal(1,"DAC setup interval under 9ns");
 if(data!==expected[13:0])$fatal(1,"DAC ramp sequence got=%d expected=%d",data,expected);
 expected=(expected+1)%2048;checked=checked+1;
end
task fill(input integer base);
begin for(i=0;i<2048;i++)begin @(negedge sc);addr=i;value=base+i;we=1;end @(negedge sc);we=0;end
endtask
task apply;
begin @(negedge sc);commit=1;@(negedge sc);commit=0;wait(busy);wait(!busy);end
endtask
initial begin
 repeat(10)@(negedge sc);rst=0;
 repeat(10)@(negedge sc);if(data!==8192)$fatal(1,"DAC boot idle");
 fill(0);
 for(i=0;i<2048;i++)begin @(negedge sc);ra=i;repeat(2)@(negedge sc);if(read_data!==i[13:0])$fatal(1,"inactive table readback");end
 on=1;apply();repeat(5)@(negedge dc);
 // Establish the exact phase/pipeline alignment, then verify >2 complete cycles.
 @(posedge dc);#1;expected=(data+1)%2048;check=1;
 repeat(5000)@(negedge sc);
 // Writing the other table must not change the active ramp.
 fill(4000);repeat(50)@(negedge sc);check=0;
 if(checked<3000)$fatal(1,"too few checked samples");
 apply();repeat(6)@(negedge dc);if(data<4000||data>6047)$fatal(1,"atomic bank switch");
 // Disabled output is the requested idle code; it is not power-down/high-Z.
 fill(7000);idle=1234;on=0;apply();repeat(6)@(negedge dc);if(data!==1234)$fatal(1,"DAC stop code");
 if(status==0)$fatal(1,"DAC heartbeat absent");
 $display("PASS dac: rising-edge stability, 2048-word readback, DDS sequence, inactive-bank writes, atomic commit and idle");$finish;
end
initial begin #1000000;$fatal(1,"DAC timeout");end
endmodule
