`timescale 1ns/1ps
module tb_display #(parameter VGA=0);
localparam WIDTH=VGA?640:1280,HEIGHT=VGA?480:720;
reg sc=0,pc=0;always #5 sc=~sc;always #(VGA?19.841:6.734) pc=~pc;
reg rst=1,wwe=0,hwe=0,twe=0,commit=0;reg[9:0]wa=0;reg[19:0]wd=0;reg[15:0]ha=0;reg[7:0]hd=0,td=0;reg[12:0]ta=0;
wire pending,hs,vs,de,bank;wire[23:0]rgb;wire[31:0]frames,frame_crc;
reg[7:0]texts[0:7199],heat[0:14399];reg[19:0]waves[0:959];
scope_display #(.VIDEO_VGA(VGA)) dut(sc,rst,pc,rst,wwe,wa,wd,hwe,ha,hd,twe,ta,td,commit,32'h80000000,pending,frames,hs,vs,de,rgb,bank,frame_crc);
integer i,file,count=0;reg capture=0;reg[11:0]rx,ry;
always @(posedge pc)begin rx<=dut.x3;ry<=dut.y3;end
always @(negedge pc)if(capture&&de&&rx<1280&&ry<720)begin
 $fwrite(file,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);count=count+1;
 if(count==WIDTH*HEIGHT)begin $fclose(file);capture=0;wait(dut.fs);@(posedge pc);@(negedge pc);$display("PIXEL_CRC32=%08x",frame_crc);$display("PASS display: %0dx%0d RGB snapshot from actual RTL pipeline",WIDTH,HEIGHT);$finish;end
end
initial begin
 $readmemh("ui_text.mem",texts);$readmemh("ui_wave.mem",waves);$readmemh("ui_hist.mem",heat);
 repeat(10)@(negedge sc);rst=0;
 for(i=0;i<960;i++)begin wa=i;wd=waves[i];wwe=1;@(negedge sc);end wwe=0;
 for(i=0;i<14400;i++)begin ha=i;hd=heat[i];hwe=1;@(negedge sc);end hwe=0;
 for(i=0;i<7200;i++)begin ta=i;td=texts[i];twe=1;@(negedge sc);end twe=0;
 commit=1;@(negedge sc);commit=0;wait(pending);wait(!pending);
 wait(dut.x_raw==0&&dut.y_raw==HEIGHT+2);@(negedge pc);
 file=$fopen("ui_rtl.ppm","wb");$fwrite(file,"P6\n%0d %0d\n255\n",WIDTH,HEIGHT);capture=1;
end
initial begin #60000000;$fatal(1,"display timeout");end
endmodule
