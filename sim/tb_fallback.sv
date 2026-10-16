`timescale 1ns/1ps
module tb_fallback;
reg clk=0,ac=0,pc=0;always #5 clk=~clk;always #50 ac=~ac;always #6.734 pc=~pc;
reg resetn=0;reg[19:0]aw=0,ar=0;reg[31:0]wd=0;reg[3:0]ws=15;reg av=0,wv=0,bready=0,arv=0,rready=0;
wire awready,wready,bv,arr,rv;wire[1:0]br,rr;wire[31:0]rd;wire[15:0]sd;wire[1:0]sk;wire sv,sl;
wire[23:0]rgb;wire hs,vs,de,irq;wire[1:0]rate;
scope_peripheral dut(.s_axi_aclk(clk),.s_axi_aresetn(resetn),.s_axi_awaddr(aw),.s_axi_awprot(0),.s_axi_awvalid(av),.s_axi_awready(awready),
.s_axi_wdata(wd),.s_axi_wstrb(ws),.s_axi_wvalid(wv),.s_axi_wready(wready),.s_axi_bresp(br),.s_axi_bvalid(bv),.s_axi_bready(bready),
.s_axi_araddr(ar),.s_axi_arprot(0),.s_axi_arvalid(arv),.s_axi_arready(arr),.s_axi_rdata(rd),.s_axi_rresp(rr),.s_axi_rvalid(rv),.s_axi_rready(rready),
.m_axis_tdata(sd),.m_axis_tkeep(sk),.m_axis_tvalid(sv),.m_axis_tready(1'b1),.m_axis_tlast(sl),.adc_clk_in(ac),.pixel_clk(pc),
.video_locked(1'b1),.adc_locked(1'b1),.adc_data(12'd0),.adc_otr(1'b0),.key_n(2'b11),.rate_sel(rate),.rgb(rgb),.hs(hs),.vs(vs),.de(de),.irq(irq));
integer seed=7010,i;reg[31:0]v;
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

integer col,j,a,b,lo,hi;reg[19:0]expected;integer written=0;
always @(negedge clk)if(dut.wave_we)written++;
initial begin repeat(20)@(negedge clk);resetn=1;wait(dut.fb_valid);#1;
if(written!=960)$fatal(1,"fallback missed columns %d",written);
for(col=0;col<960;col++)begin
 a=(col*16384+959)/960;b=((col+1)*16384+959)/960;lo=4095;hi=0;
 for(j=a;j<b;j++)begin
  if((dut.ring[(dut.sa_s+j)&16383]&4095)<lo)lo=dut.ring[(dut.sa_s+j)&16383]&4095;
  if((dut.ring[(dut.sa_s+j)&16383]&4095)>hi)hi=dut.ring[(dut.sa_s+j)&16383]&4095;
 end
 expected=(609-((hi*539)>>12))|((609-((lo*539)>>12))<<10);
 if(dut.display.wave[col]!==expected)$fatal(1,"fallback column %d got %x expected %x",col,dut.display.wave[col],expected);
end
$display("PASS fallback: all 16384 points included in 960 exact Min/Max columns without PS or DDR");$finish;end
initial begin #10000000;$fatal(1,"fallback timeout");end
endmodule
