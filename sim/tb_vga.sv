`timescale 1ns/1ps
module tb_vga;
 reg clk=0,rst=1;always #5 clk=~clk;wire[11:0]x,y;wire de,hs,vs,fs;
 scope_video_timing #(.H_ACTIVE(640),.H_FRONT(16),.H_SYNC(96),.H_BACK(48),.V_ACTIVE(480),.V_FRONT(10),.V_SYNC(2),.V_BACK(33)) dut(clk,rst,x,y,de,hs,vs,fs);
 integer act=0,h=0,v=0,f=0;
 initial begin repeat(4)@(negedge clk);rst=0;repeat(800*525)begin @(negedge clk);if(de)act++;if(hs)h++;if(vs)v++;if(fs)f++;end
 if(act!=640*480||h!=96*525||v!=2*800||f!=1)$fatal(1,"VGA geometry");$display("PASS vga: 800x525 totals, 640x480 active, 96/2 sync");$finish;end
endmodule
