`timescale 1ns/1ps
module tb_raster;
reg clk=0,rst=1,clear=0,pv=0,ready=1;always #5 clk=~clk;reg[7:0]px=0;reg[6:0]py=0;
wire hv,busy;wire[13:0]addr;wire[31:0]drops;integer hits=0,i;
scope_raster dut(clk,rst,clear,pv,px,py,ready,hv,addr,busy,drops);
always @(posedge clk)if(hv&&ready)begin hits=hits+1;if(addr>=14400)$fatal(1,"raster out of bounds");end
task point(input[7:0]x,input[6:0]y);begin wait(!busy);@(negedge clk);px=x;py=y;pv=1;@(negedge clk);pv=0;wait(busy);wait(!busy);end endtask
initial begin repeat(4)@(negedge clk);rst=0;
point(10,10);point(10,80);point(30,60);point(0,89);if(hits!=92)$fatal(1,"raster exactly-once endpoints got %d",hits);
ready=0;@(negedge clk);px=0;py=0;pv=1;@(negedge clk);pv=0;wait(hv);
repeat(10)begin @(negedge clk);if(!hv)$fatal(1,"hit lost under backpressure");end
ready=1;wait(!busy);if(hits!=181||drops!=0)$fatal(1,"raster ready/count %d",hits);
$display("PASS raster: vertical, diagonal, eye wrap, bounded addresses, held hit under backpressure, exact endpoints");$finish;end
initial begin #100000;$fatal(1,"raster timeout");end
endmodule
