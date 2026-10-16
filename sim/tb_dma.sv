`timescale 1ns/1ps
module tb_dma;
reg bc=0,ac=0;always #5 bc=~bc;always #50 ac=~ac;
reg rst=1,start=0,ready=0;reg[31:0]count=1000;reg[15:0]sample=0;wire[15:0]data;wire[1:0]keep;wire valid,last;
wire[31:0]dropped,produced;wire active;wire[12:0]level;integer received=0;reg[15:0]prev;reg[31:0]rng=7010;
scope_dma_stream dut(ac,rst,sample,start,count,bc,rst,data,keep,valid,ready,last,dropped,produced,active,level,1'b0,64'b0,);
always @(posedge ac)if(!rst)sample<=sample+1;
always @(negedge bc)if(!rst)begin rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};if(received<1000)ready<=rng[0];else ready<=0;end
always @(posedge bc)if(valid&&ready)begin
 if(received&&data!==prev+16'd1)$fatal(1,"DMA sequence lost/duplicated sample");
 if(keep!=3||last!==(received==999))$fatal(1,"AXIS keep/TLAST");
 prev<=data;received<=received+1;
end
initial begin repeat(20)@(negedge bc);rst=0;repeat(100)@(negedge ac);
@(negedge bc);start=1;@(negedge bc);start=0;wait(received==1000);repeat(100)@(negedge bc);
if(dropped!=0||produced!=1000)$fatal(1,"DMA count");
count=5000;start=1;@(negedge bc);start=0;wait(dropped!=0);
if(active)$fatal(1,"overflow failed to stop stream");
$display("PASS dma: random backpressure, 1000 ordered words, exact TLAST, explicit overflow abort/drop");$finish;end
initial begin #2000000;$fatal(1,"DMA timeout");end
endmodule
