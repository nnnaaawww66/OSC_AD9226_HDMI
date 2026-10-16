`timescale 1ns/1ps
module tb_video;
reg clk=0,rst=1;always #5 clk=~clk;wire[11:0]x,y;wire de,hs,vs,fs;
scope_video_timing dut(clk,rst,x,y,de,hs,vs,fs);
integer pixels=0,active=0,hsn=0,vsn=0,frames=0;
initial begin repeat(3)@(negedge clk);rst=0;
repeat(1650*750*2)begin
 @(negedge clk);pixels=pixels+1;if(de)active=active+1;if(hs)hsn=hsn+1;if(vs)vsn=vsn+1;if(fs)frames=frames+1;
end
if(active!=1280*720*2||hsn!=40*750*2||vsn!=1650*5*2||frames!=2)$fatal(1,"video geometry/sync mismatch %0d %0d %0d %0d",active,hsn,vsn,frames);
$display("PASS video: 1650x750 totals, 1280x720 active, 40/5 sync, two frames");$finish;end
endmodule
