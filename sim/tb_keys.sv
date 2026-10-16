`timescale 1ns/1ps
module tb_keys;
reg clk=0,rst=1;always #5 clk=~clk;reg[1:0] kn=3;wire[31:0]ev;
scope_keys #(.DEBOUNCE(3),.LONG_TICKS(30))dut(clk,rst,kn,ev);
task step(input[1:0] k,input integer n);begin @(negedge clk);kn=k;repeat(n)@(negedge clk);end endtask
initial begin repeat(5)@(negedge clk);rst=0;
step(2,2);step(3,2);step(2,12);step(3,15);
if(ev[31:16]!=1||ev[2:0]!=1)$fatal(1,"key debounce/short");
step(2,10);step(0,10);step(3,15);
if(ev[31:16]!=2||ev[2:0]!=3)$fatal(1,"combo generated competing events");
step(0,60);step(3,15);if(ev[31:16]!=3||ev[2:0]!=7)$fatal(1,"combo long/release duplicate");
$display("PASS keys: bounce, short, staggered combo, long, no duplicate release");$finish;end
endmodule
