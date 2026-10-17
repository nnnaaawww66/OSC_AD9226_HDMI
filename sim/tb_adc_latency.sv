`timescale 1ns/1ps
// Behavioral AD9226: seven-cycle converter pipeline followed by an IOB receive register.
// 2..4ns forward FPGA I/O allowance + 3.5..10ns ADC/board data delay are swept.
// Real full-design min/max I/O delays are separately checked by post-route STA.
module tb_adc_latency;
real period=100.0,phase=0.0,delay_ns=5.5;reg fwd=0,receive=0;integer k=-1,j,i,c,checks=0;
reg[15:0]pipe[0:6];reg[15:0]pins=0,q=0;reg checking=0;reg[15:0]expected;
always #(period/2)fwd=~fwd;
always @(posedge fwd)begin
 k=k+1;pipe[0]<={3'b0,(k%11==0),12'(k)};
 for(j=1;j<7;j=j+1)pipe[j]<=pipe[j-1];
 pins<=#(delay_ns) pipe[6];
 receive<=#(phase)1;receive<=#(phase+period/2)0;
end
always @(posedge receive)begin
 q=pins;expected={3'b0,((k-8)%11==0),12'(k-8)};
 if(checking)begin
  if(q!==expected)$fatal(1,"ADC prior-conversion latency/OTR failed k=%d got=%x expected=%x delay=%f",k,q,expected,delay_ns);
  checks=checks+1;
 end
end
initial begin
 for(i=0;i<7;i=i+1)pipe[i]=0;
 for(c=0;c<4;c=c+1)begin
  checking=0;period=c==0?100.0:c==1?40.0:c==2?20.0:1000.0/65.0;phase=c<2?0.0:1000.0/65.0/4;
  for(i=0;i<2;i=i+1)begin
   checking=0;delay_ns=i==0?5.5:14.0;repeat(40)@(negedge fwd);checking=1;repeat(100)@(negedge fwd);checking=0;
  end
 end
 if(checks<800)$fatal(1,"Too few ADC latency checks");
 $display("PASS adc_latency: seven converter cycles plus prior-conversion receive, ordered codes/OTR, four rates, min/max data arrival");$finish;
end
initial begin #1000000;$fatal(1,"ADC latency timeout");end
endmodule
