`timescale 1ns / 1ps
module scope_clocks
    #(parameter VIDEO_VGA = 0)
    (input wire clk_50m,
     input wire [1 : 0] rate_sel,
     output wire clk_sys, clk_adc, clk_pixel, clk_serial,
     output wire locked_adc, locked_video);
    wire fb_a, fb_ab, sys_raw;
    wire [3 : 0] adc_raw;
    wire low_pair, high_pair;
    // 50 * 13 = 650MHz VCO; output0 permits a fractional divide of 6.5.
    MMCME2_BASE #(.CLKIN1_PERIOD(20.0),
                  .CLKFBOUT_MULT_F(13.0),
                  .DIVCLK_DIVIDE(1),
                  .CLKOUT0_DIVIDE_F(6.5),
                  .CLKOUT1_DIVIDE(65),
                  .CLKOUT2_DIVIDE(26),
                  .CLKOUT3_DIVIDE(13),
                  .CLKOUT4_DIVIDE(10))
        adc_mmcm(.CLKIN1(clk_50m),
                 .CLKFBIN(fb_ab),
                 .CLKFBOUT(fb_a),
                 .CLKFBOUTB(),
                 .CLKOUT0(sys_raw),
                 .CLKOUT0B(),
                 .CLKOUT1(adc_raw[0]),
                 .CLKOUT1B(),
                 .CLKOUT2(adc_raw[1]),
                 .CLKOUT2B(),
                 .CLKOUT3(adc_raw[2]),
                 .CLKOUT3B(),
                 .CLKOUT4(adc_raw[3]),
                 .CLKOUT5(),
                 .CLKOUT6(),
                 .LOCKED(locked_adc),
                 .PWRDWN(1'b0),
                 .RST(1'b0));
    BUFG afb(.I(fb_a),
             .O(fb_ab));
    BUFG sysbuf(.I(sys_raw),
                .O(clk_sys));
    BUFGMUX lowmux(.I0(adc_raw[0]),
                   .I1(adc_raw[1]),
                   .S(rate_sel[0]),
                   .O(low_pair));
    BUFGMUX highmux(.I0(adc_raw[2]),
                    .I1(adc_raw[3]),
                    .S(rate_sel[0]),
                    .O(high_pair));
    BUFGMUX ratemux(.I0(low_pair),
                    .I1(high_pair),
                    .S(rate_sel[1]),
                    .O(clk_adc));
    // Cascade is required for EXACT 74.25 and 371.25MHz from the 50MHz board clock.
    // 100 * 37.125 / 5 = 742.5MHz VCO, /10 pixel, /2 serializer.
    wire fb_v, fb_vb, pix_raw, ser_raw;
    MMCME2_BASE #(.CLKIN1_PERIOD(10.0),
                  .CLKFBOUT_MULT_F(VIDEO_VGA ? 31.5 : 37.125),
                  .DIVCLK_DIVIDE(5),
                  .CLKOUT0_DIVIDE_F(VIDEO_VGA ? 25.0 : 10.0),
                  .CLKOUT1_DIVIDE(VIDEO_VGA ? 5 : 2))
        video_mmcm(.CLKIN1(clk_sys),
                   .CLKFBIN(fb_vb),
                   .CLKFBOUT(fb_v),
                   .CLKFBOUTB(),
                   .CLKOUT0(pix_raw),
                   .CLKOUT0B(),
                   .CLKOUT1(ser_raw),
                   .CLKOUT1B(),
                   .CLKOUT2(),
                   .CLKOUT2B(),
                   .CLKOUT3(),
                   .CLKOUT3B(),
                   .CLKOUT4(),
                   .CLKOUT5(),
                   .CLKOUT6(),
                   .LOCKED(locked_video),
                   .PWRDWN(1'b0),
                   .RST(~locked_adc));
    BUFG vfb(.I(fb_v),
             .O(fb_vb));
    BUFG pbuf(.I(pix_raw),
              .O(clk_pixel));
    BUFG sbuf(.I(ser_raw),
              .O(clk_serial));
endmodule
