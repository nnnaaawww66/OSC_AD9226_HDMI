`timescale 1ns/1ps
module tb_clocks;
reg refclk=0;always #10 refclk=~refclk;
reg[1:0]sel=0;wire sys,adc,fwd,pix,ser,al,vl;
scope_clocks dut(refclk,sel,sys,adc,fwd,pix,ser,al,vl);
function real absreal(input real x);absreal=x<0?-x:x;endfunction
realtime t0,t1,t2,period,shift;integer i;
initial begin
 wait(al&&vl);repeat(30)@(posedge sys);
 for(i=0;i<4;i=i+1) begin
  @(negedge sys);sel=i;repeat(200)@(posedge sys);
  period=i==0?100.0:i==1?40.0:i==2?20.0:1000.0/65.0;
  @(posedge fwd);t0=$realtime;@(posedge fwd);t1=$realtime;
  if(absreal((t1-t0)-period)>0.020)$fatal(1,"forward period rate=%0d measured=%f",i,t1-t0);
  if(i>=2) begin
   @(posedge adc);t2=$realtime;
   shift=1000.0/65.0/4;
   if(absreal((t2-t1)-shift)>0.025)$fatal(1,"receive phase rate=%0d delta=%f expected=%f",i,t2-t1,shift);
  end
  $display("CLOCK rate=%0d period=%f",i,period);
 end
 $display("PASS clocks: all 4 nominal rates and controlled receive phase in Xilinx primitives");$finish;
end
initial begin #200000;$fatal(1,"clock lock/test timeout");end
endmodule
