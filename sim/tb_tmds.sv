
`timescale 1ns/1ps
module tb_tmds;
 reg clk=0,rst=1;always #5 clk=~clk;reg[10:0]input_word=0;wire[9:0]out;
 reg[10:0]data[0:2047];reg[9:0]expected[0:2047];integer i;
 encode dut(clk,rst,input_word[7:0],input_word[8],input_word[9],input_word[10],out);
 initial begin $readmemh("tmds_input.mem",data);$readmemh("tmds_expected.mem",expected);
 repeat(5)@(negedge clk);rst=0;
 for(i=0;i<2050;i++)begin
 input_word=i<2048?data[i]:0;@(posedge clk);#2;
 if(i>=2&&out!==expected[i-2])$fatal(1,"TMDS mismatch at %d got %x expected %x",i-2,out,expected[i-2]);
 @(negedge clk);
 end
 $display("PASS tmds: 2048 golden control/video symbols, running disparity, all byte values, seed7010");$finish;end
endmodule
