`timescale 1ns/1ps
module tb_mailbox;
reg sc=0,dc=0;always #5 sc=~sc;always #7 dc=~dc;
reg sr=1,dr=1,send=0;reg[63:0] data=0;wire busy,valid;wire[63:0] got;
scope_mailbox #(.WIDTH(64)) dut(sc,sr,data,send,busy,dc,dr,got,valid);
integer sent=0,received=0,i;
always @(posedge dc)if(valid)begin
 if(got!=={32'(received),32'(~received)})$fatal(1,"torn/lost mailbox data");received=received+1;end
initial begin repeat(5)@(negedge sc);sr=0;dr=0;
for(i=0;i<1000;i=i+1)begin
 wait(!busy);@(negedge sc);data={32'(i),32'(~i)};send=1;@(negedge sc);send=0;
 wait(busy);wait(!busy);end
repeat(10)@(negedge dc);if(received!=1000)$fatal(1,"mailbox lost messages");
$display("PASS mailbox: 1000 coherent transfers at asynchronous clocks");$finish;end
initial begin #1000000;$fatal(1,"mailbox timeout");end
endmodule
