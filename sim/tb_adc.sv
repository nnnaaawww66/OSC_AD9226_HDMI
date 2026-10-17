`timescale 1ns/1ps
module tb_adc;
reg clk=0,ac=0,pc=0;always #5 clk=~clk;always #50 ac=~ac;always #6.734 pc=~pc;
reg resetn=0;reg[19:0]aw=0,ar=0;reg[31:0]wd=0;reg[3:0]ws=15;reg av=0,wv=0,bready=0,arv=0,rready=0;
wire awready,wready,bv,arr,rv;wire[1:0]br,rr;wire[31:0]rd;wire[15:0]sd;wire[1:0]sk;wire sv,sl;reg stream_ready=1;reg[11:0]pins=0;reg pin_otr=0;
wire[23:0]rgb;wire hs,vs,de,irq;wire[1:0]rate;
scope_peripheral dut(.s_axi_aclk(clk),.s_axi_aresetn(resetn),.s_axi_awaddr(aw),.s_axi_awprot(0),.s_axi_awvalid(av),.s_axi_awready(awready),
.s_axi_wdata(wd),.s_axi_wstrb(ws),.s_axi_wvalid(wv),.s_axi_wready(wready),.s_axi_bresp(br),.s_axi_bvalid(bv),.s_axi_bready(bready),
.s_axi_araddr(ar),.s_axi_arprot(0),.s_axi_arvalid(arv),.s_axi_arready(arr),.s_axi_rdata(rd),.s_axi_rresp(rr),.s_axi_rvalid(rv),.s_axi_rready(rready),
.m_axis_tdata(sd),.m_axis_tkeep(sk),.m_axis_tvalid(sv),.m_axis_tready(stream_ready),.m_axis_tlast(sl),.adc_clk_in(ac),.pixel_clk(pc),
.video_locked(1'b1),.adc_locked(1'b1),.adc_data(pins),.adc_otr(pin_otr),.key_n(2'b11),.rate_sel(rate),.rgb(rgb),.hs(hs),.vs(vs),.de(de),.irq(irq));
task write(input[19:0]addr,input[31:0]value,input integer skew,input[1:0]resp);
reg[1:0]saved;begin
 fork
 begin repeat(skew%5)@(negedge clk);aw=addr;av=1;do @(posedge clk);while(!awready);@(negedge clk);av=0;end
 begin repeat((skew+2)%5)@(negedge clk);wd=value;wv=1;do @(posedge clk);while(!wready);@(negedge clk);wv=0;end
 join
 wait(bv);saved=br;repeat(3)begin @(negedge clk);if(!bv||br!==saved)$fatal(1,"B response not held");end
 if(br!==resp)$fatal(1,"write response addr=%x got=%d",addr,br);
 bready=1;@(negedge clk);bready=0;
end endtask
task read(input[19:0]addr,output[31:0]value,input[1:0]resp);
reg[31:0]saved;begin @(negedge clk);ar=addr;arv=1;do @(posedge clk);while(!arr);@(negedge clk);arv=0;
 wait(rv);saved=rd;repeat(3)begin @(negedge clk);if(!rv||rd!==saved)$fatal(1,"R response not held");end
 if(rr!==resp)$fatal(1,"read response addr=%x got=%d",addr,rr);value=rd;rready=1;@(negedge clk);rready=0;
end endtask
integer i;reg[31:0]v;reg[31:0]before_otr;
initial begin
 repeat(20)@(negedge clk);resetn=1;write('h64,1,0,0);
 write('h08,32'h00880001,0,0);do begin read('h24,v,0);end while(v&512);
 repeat(5)@(negedge ac);before_otr=dut.otr_count;
 for(i=0;i<200;i=i+1)begin
  @(negedge ac);pins=(i<24)?(12'b1<<(i%12)):(i*37);pin_otr=i%7==0;
  @(posedge ac);#1;
  if(dut.adc_q!==pins||dut.otr_q!==pin_otr||dut.sample!==pins||dut.otr!==pin_otr)$fatal(1,"ADC bit order / OTR input register mismatch i=%d",i);
 end
 @(negedge ac);pin_otr=0;repeat(3)@(negedge ac);
 if(dut.otr_count-before_otr!=29)$fatal(1,"OTR count %d expected29",dut.otr_count-before_otr);
 write('h08,32'h00880041,0,0);do begin read('h24,v,0);end while(v&512);
 repeat(5)@(negedge ac);
 for(i=0;i<32;i=i+1)begin
  @(negedge ac);pins=i*127;@(posedge ac);#1;
  if(dut.sample!=={~pins[11],pins[10:0]})$fatal(1,"Two's complement conversion");
 end
 $display("PASS adc: walking bits, 200 codes, registered OTR/count, offset/twos encoding");$finish;
end
initial begin #1000000;$fatal(1,"ADC timeout");end
endmodule
