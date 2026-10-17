`timescale 1ns / 1ps
module scope_display
    #(parameter HW = 160, HH = 90, VIDEO_VGA = 0)
    (input wire sys_clk, sys_rst,
     input wire pixel_clk, pixel_rst,
     input wire wave_we,
     input wire [9 : 0] wave_addr,
     input wire [19 : 0] wave_data,
     input wire hist_we,
     input wire [15 : 0] hist_addr,
     input wire [7 : 0] hist_data,
     input wire text_we,
     input wire [12 : 0] text_addr,
     input wire [7 : 0] text_data,
     input wire commit,
     input wire [31 : 0] meta,
     output wire pending,
     output reg [31 : 0] frame_count = 0,
     output wire hs, vs, de,
     output reg [23 : 0] rgb = 0,
     output wire front_bank);
    (* ram_style = "block" *) reg [19 : 0] wave[0 : 2047];
    (* ram_style = "block" *) reg [7 : 0] histogram[0 : 32767];
    (* ram_style = "block" *) reg [7 : 0] characters[0 : 16383];
    (* rom_style = "block" *) reg [7 : 0] font[0 : 2047];
    initial begin
        $readmemh("font.mem", font);
        $readmemh("screen.mem", characters);
    end
    reg bank_sys = 0, req = 0, ack = 0;
    (* DONT_TOUCH = "TRUE" *) reg [31 : 0] meta_hold = 0;
    (* DONT_TOUCH = "TRUE" *) reg [31 : 0] meta_pix = 0;
    (* ASYNC_REG = "TRUE" *) reg ack_meta = 0, ack_sync = 0, req_meta = 0, req_sync = 0;
    reg bank_pix = 1;
    assign front_bank = ack_sync;
    assign pending = req != ack_sync;
    wire [11 : 0] x_raw, y_raw;
    wire [11 : 0] x = VIDEO_VGA ? (x_raw << 1) : x_raw, y = VIDEO_VGA ? ((y_raw * 3) >> 1) : y_raw;
    wire hs0, vs0, de0, fs, hs_active, vs_active;
    assign hs0 = VIDEO_VGA ? ~hs_active : hs_active;
    assign vs0 = VIDEO_VGA ? ~vs_active : vs_active;
    scope_video_timing #(.H_ACTIVE(VIDEO_VGA ? 640 : 1280),
                         .H_FRONT(VIDEO_VGA ? 16 : 110),
                         .H_SYNC(VIDEO_VGA ? 96 : 40),
                         .H_BACK(VIDEO_VGA ? 48 : 220),
                         .V_ACTIVE(VIDEO_VGA ? 480 : 720),
                         .V_FRONT(VIDEO_VGA ? 10 : 5),
                         .V_SYNC(VIDEO_VGA ? 2 : 5),
                         .V_BACK(VIDEO_VGA ? 33 : 20))
        timing(.clk(pixel_clk),
               .rst(pixel_rst),
               .x(x_raw),
               .y(y_raw),
               .hs(hs_active),
               .vs(vs_active),
               .de(de0),
               .frame_start(fs));
    always @(posedge sys_clk) begin
        if (sys_rst) begin
            bank_sys <= 0;
            req <= 0;
            ack_meta <= 0;
            ack_sync <= 0;
            meta_hold <= 0;
        end else begin
            ack_meta <= ack;
            ack_sync <= ack_meta;
            if (commit && !pending) begin
                meta_hold <= meta;
                req <= ~req;
                bank_sys <= ~bank_sys;
            end
            if (wave_we && !pending)
                wave[{bank_sys, wave_addr}] <= wave_data;
            if (hist_we && !pending && hist_addr < HW * HH)
                histogram[{bank_sys, hist_addr[13 : 0]}] <= hist_data;
            if (text_we && !pending && text_addr < 7200)
                characters[{bank_sys, text_addr}] <= text_data;
        end
    end
    always @(posedge pixel_clk) begin
        if (pixel_rst) begin
            req_meta <= 0;
            req_sync <= 0;
            ack <= 0;
            bank_pix <= 1;
            meta_pix <= 0;
            frame_count <= 0;
        end else begin
            req_meta <= req;
            req_sync <= req_meta;
            if (fs) begin
                frame_count <= frame_count + 1;
                if (req_sync != ack) begin
                    ack <= req_sync;
                    bank_pix <= ~bank_pix;
                    meta_pix <= meta_hold;
                end
            end
        end
    end
    // Pixel pipeline: address -> memory -> font -> composite; sync follows every stage.
    wire plot = x >= 20 && x < 980 && y >= 70 && y < 610;
    wire [9 : 0] wx = plot ? x - 20 : 0;
    wire [8 : 0] hx = plot ? (x - 20) / 6 : 0;
    wire [7 : 0] hy = plot ? (y - 70) / 6 : 0;
    reg [11 : 0] x0 = 0, y0 = 0;
    reg [19 : 0] hx_product = 0, hy_product = 0;
    reg [9 : 0] wx_address = 0;
    reg [12 : 0] char_address = 0;
    reg [3 : 0] glyph_row0 = 0;
    reg [2 : 0] glyph_bit0 = 0;
    wire title_glyph = x >= 24 && x < 184 && y >= 12 && y < 44;
    wire metric_glyph = x >= 1016 && x < 1256 &&
                        ((y >= 112 && y < 144) || (y >= 240 && y < 272) || (y >= 352 && y < 384));
    wire [5 : 0] metric_row = y < 200 ? 6'd7 : (y < 312 ? 6'd15 : 6'd22);
    wire [11 : 0] metric_y = y < 200 ? y - 112 : (y < 312 ? y - 240 : y - 352);
    always @(posedge pixel_clk) begin
        x0 <= x;
        y0 <= y;
        wx_address <= wx;
        char_address <= title_glyph    ? 13'd3 + ((x - 24) >> 4)
                        : metric_glyph ? metric_row * 160 + 127 + ((x - 1016) >> 4)
                                       : (y >> 4) * 160 + (x >> 3);
        glyph_row0 <= title_glyph ? ((y - 12) >> 1) : metric_glyph ? (metric_y >> 1) : y[3 : 0];
        glyph_bit0 <= title_glyph ? ((x - 24) >> 1) : metric_glyph ? ((x - 1016) >> 1) : x[2 : 0];
        hx_product <= plot ? (x - 20) * 20'd683 : 20'd0;
        hy_product <= plot ? (y - 70) * 20'd683 : 20'd0;
    end
    wire [13 : 0] hist_read_index = (hy_product >> 12) * HW + (hx_product >> 12);
    reg [19 : 0] wq = 0;
    wire [19 : 0] pair_q;
    wire [9 : 0] pair_addr = wx_address + 1'b1;
    generate
        if (VIDEO_VGA) begin : g_vga_envelope
            (* ram_style = "block" *) reg [19 : 0] pair_memory[0 : 2047];
            reg [19 : 0] q = 0;
            always @(posedge sys_clk)
                if (wave_we && !pending)
                    pair_memory[{bank_sys, wave_addr}] <= wave_data;
            always @(posedge pixel_clk)
                q <= pair_memory[{bank_pix, pair_addr}];
            assign pair_q = q;
        end else begin
            assign pair_q = 0;
        end
    endgenerate
    wire [9 : 0] pair_top = wq[9 : 0] < pair_q[9 : 0] ? wq[9 : 0] : pair_q[9 : 0];
    wire [9 : 0] pair_bottom = wq[19 : 10] > pair_q[19 : 10] ? wq[19 : 10] : pair_q[19 : 10];

    reg [7 : 0] hq = 0, cq = 32, fq = 0;
    reg [11 : 0] x1 = 0, y1 = 0, x2 = 0, y2 = 0, x3 = 0, y3 = 0;
    reg [19 : 0] w2 = 0, w3 = 0;
    reg [7 : 0] h2 = 0, h3 = 0;
    reg [3 : 0] hsp = 0, vsp = 0, dep = 0;
    reg [3 : 0] row1 = 0;
    reg [2 : 0] bit1 = 0, bit2 = 0;
    reg [7 : 0] font3 = 0;
    reg [2 : 0] bit3 = 0;
    always @(posedge pixel_clk) begin
        x1 <= x0;
        y1 <= y0;
        x2 <= x1;
        y2 <= y1;
        x3 <= x2;
        y3 <= y2;
        hsp <= {hsp[2 : 0], hs0};
        vsp <= {vsp[2 : 0], vs0};
        dep <= {dep[2 : 0], de0};
        wq <= wave[{bank_pix, wx_address}];
        hq <= histogram[{bank_pix, hist_read_index}];
        cq <= characters[bank_pix * 8192 + char_address];
        row1 <= glyph_row0;
        bit1 <= glyph_bit0;
        fq <= font[{cq[6 : 0], row1}] |
              ((VIDEO_VGA && row1 < 15) ? font[{cq[6 : 0], row1 + 4'd1}] : 8'd0);
        bit2 <= bit1;
        w2 <= VIDEO_VGA ? {pair_bottom, pair_top} : wq;
        h2 <= hq;
        font3 <= fq;
        bit3 <= bit2;
        w3 <= w2;
        h3 <= h2;
    end
    reg hs_q = 0, vs_q = 0, de_q = 0;
    assign hs = hs_q;
    assign vs = vs_q;
    assign de = de_q;
    wire in_plot = x3 >= 20 && x3 < 980 && y3 >= 70 && y3 < 610;
    wire grid = (x3 == 20) || (x3 == 116) || (x3 == 212) || (x3 == 308) || (x3 == 404) ||
                (x3 == 500) || (x3 == 596) || (x3 == 692) || (x3 == 788) || (x3 == 884) ||
                (y3 == 70) || (y3 == 124) || (y3 == 178) || (y3 == 232) || (y3 == 286) ||
                (y3 == 340) || (y3 == 394) || (y3 == 448) || (y3 == 502) || (y3 == 556);
    wire trace = in_plot && (VIDEO_VGA ? (y3 + 1 >= w3[9 : 0]) : (y3 >= w3[9 : 0])) &&
                 y3 <= w3[19 : 10] && meta_pix[31];
    wire [23 : 0] heat = h3 < 16    ? {8'd0, h3 << 3, 8'h40}
                         : h3 < 64  ? {8'd0, 8'hc0, h3 << 2}
                         : h3 < 128 ? {h3 << 1, 8'hff, 8'd0}
                                    : {8'hff, 8'hff - (h3 << 1), 8'd0};
    wire header_tab = y3 >= 8 && y3 < 34 && x3 >= 240 && x3 < 912;
    wire selected_tab = (meta_pix[2 : 0] == 0 && x3 >= 240 && x3 < 328) ||
                        (meta_pix[2 : 0] == 1 && x3 >= 336 && x3 < 424) ||
                        (meta_pix[2 : 0] == 2 && x3 >= 432 && x3 < 520) ||
                        (meta_pix[2 : 0] == 3 && x3 >= 528 && x3 < 616) ||
                        (meta_pix[2 : 0] == 4 && x3 >= 624 && x3 < 712) ||
                        (meta_pix[2 : 0] == 5 && x3 >= 720 && x3 < 808) ||
                        (meta_pix[2 : 0] == 6 && x3 >= 816 && x3 < 904);
    wire card = x3 >= 1008 && x3 < 1264 &&
                ((y3 >= 80 && y3 < 192) || (y3 >= 200 && y3 < 304) || (y3 >= 312 && y3 < 416) ||
                 (y3 >= 432 && y3 < 610));
    wire card_edge = card && (x3 == 1008 || x3 == 1263 || y3 == 80 || y3 == 191 || y3 == 200 ||
                              y3 == 303 || y3 == 312 || y3 == 415 || y3 == 432 || y3 == 609);
    wire big_value =
             x3 >= 1016 && x3 < 1256 &&
             ((y3 >= 112 && y3 < 144) || (y3 >= 240 && y3 < 272) || (y3 >= 352 && y3 < 384));
    wire soft_trace = in_plot && meta_pix[31] && w3[19 : 10] >= 70 && y3 + 1 >= w3[9 : 0] &&
                      y3 <= w3[19 : 10] + 1;
    always @(posedge pixel_clk) begin
        hs_q <= hsp[3];
        vs_q <= vsp[3];
        de_q <= dep[3];
        rgb <= 24'h0b111b;
        if (y3 < 60 || y3 >= 630)
            rgb <= 24'h111d2b;
        if (in_plot) begin
            rgb <= grid ? 24'h202e3e : 24'h090f18;
            if ((x3 == 500 || y3 == 340) && (x3[3 : 0] < 8 && y3[3 : 0] < 8))
                rgb <= 24'h415067;
            if ((meta_pix[2 : 0] == 1 || meta_pix[2 : 0] == 2) && meta_pix[31] && h3 != 0)
                rgb <= heat;
            else begin
                if (soft_trace)
                    rgb <= 24'h6b522c;
                if (trace)
                    rgb <= meta_pix[2 : 0] == 3 ? 24'hb59aff : 24'hffce73;
            end
            if (x3 == 500 && y3 < 80 && meta_pix[2 : 0] != 3)
                rgb <= 24'hf2a65a;
        end
        if (card)
            rgb <= card_edge ? 24'h27374a : 24'h111e2c;
        if (x3 >= 1008 && x3 < 1011 &&
            ((y3 >= 80 && y3 < 192) || (y3 >= 200 && y3 < 304) || (y3 >= 312 && y3 < 416)))
            rgb <= y3 < 200 ? 24'h61c8e0 : 24'hffce73;
        if (header_tab)
            rgb <= selected_tab ? 24'h254354 : 24'h142333;
        if (header_tab && selected_tab && y3 == 33)
            rgb <= 24'h61c8e0;
        if (x3 >= 1024 && x3 < 1256 && y3 >= 8 && y3 < 48)
            rgb <= meta_pix[7] ? 24'h183b35 : 24'h49342b;
        if (y3 == 60 || y3 == 620)
            rgb <= 24'h2b3c50;
        if (y3 >= 630 && y3 < 634)
            rgb <= 24'h375367;
        if (meta_pix[9] && x3 >= 32 && x3 < 352 && y3 >= 76 && y3 < 464) begin
            rgb <= (x3 == 32 || x3 == 351 || y3 == 76 || y3 == 463) ? 24'h4c6a81 : 24'h172b3d;
            if (y3 >= ((7 + meta_pix[14 : 10]) * 16) && y3 < ((8 + meta_pix[14 : 10]) * 16))
                rgb <= 24'h315467;
        end
        if ((font3[7 - bit3] || (VIDEO_VGA && bit3 < 7 && font3[6 - bit3])) &&
            !(y3 < 12 && x3 >= 24 && x3 < 184)) begin
            rgb <= 24'hd3dfed;
            if (y3 < 60)
                rgb <= 24'he9f2fb;
            if (y3 >= 64 && y3 < 86 && x3 < 980)
                rgb <= 24'hffce73;
            if (big_value)
                rgb <= 24'hebf4ff;
            if (x3 >= 1016 &&
                ((y3 >= 80 && y3 < 104) || (y3 >= 208 && y3 < 232) || (y3 >= 320 && y3 < 344)))
                rgb <= 24'h83a4c1;
            if (y3 >= 640 && y3 < 656)
                rgb <= 24'hffce73;
            if (y3 >= 672)
                rgb <= 24'h91aac1;
        end
        if (pixel_rst) begin
            rgb <= 0;
            hs_q <= 0;
            vs_q <= 0;
            de_q <= 0;
        end
    end
endmodule
