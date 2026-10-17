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
     input wire [15 : 0] text_data,
     input wire commit,
     input wire [31 : 0] meta,
     output wire pending,
     output reg [31 : 0] frame_count = 0,
     output wire hs, vs, de,
     output reg [23 : 0] rgb = 0,
     output wire front_bank,
     output reg [31:0] frame_crc = 0);
    wire fs;
    function [31:0] crc_rgb;
        input [31:0] seed;
        input [23:0] pixel;
        reg [31:0] c;
        integer b;
        begin
            c = seed;
            // Reflected IEEE CRC32; byte order R, G, B, LSB first within each byte.
            for (b=0; b<24; b=b+1) begin
                if (c[0] ^ pixel[(2-b/8)*8 + b%8]) c=(c>>1)^32'hedb88320;
                else c=c>>1;
            end
            crc_rgb=c;
        end
    endfunction
    reg [31:0] crc_state = 32'hffffffff;
    always @(posedge pixel_clk) begin
        if (pixel_rst) begin crc_state <= 32'hffffffff; frame_crc <= 0; end
        else if (fs) begin frame_crc <= ~crc_state; crc_state <= 32'hffffffff; end
        else if (de) crc_state <= crc_rgb(crc_state, rgb);
    end
    (* ram_style = "block" *) reg [19 : 0] wave[0 : 2047];
    (* ram_style = "block" *) reg [7 : 0] histogram[0 : 32767];
    (* ram_style = "block" *) reg [15 : 0] characters[0 : 16383];
    (* rom_style = "block" *) reg [15 : 0] font_hi[0 : 7151];
    (* rom_style = "block" *) reg [15 : 0] font_mid[0 : 7151];
    (* rom_style = "block" *) reg [15 : 0] font_lo[0 : 7151];
    initial begin
        $readmemh("font_hi.mem", font_hi);
        $readmemh("font_mid.mem", font_mid);
        $readmemh("font_lo.mem", font_lo);
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
    // Logical plot coordinates retain the proven 960-column acquisition map.
    // Text is sampled in native 1920x1080 pixels, never enlarged from 720p.
    wire [11 : 0] x = VIDEO_VGA ? (x_raw << 1) : (x_raw*2)/3;
    wire [11 : 0] y = VIDEO_VGA ? ((y_raw * 3) >> 1) : (y_raw*2)/3;
    wire [11 : 0] font_x = VIDEO_VGA ? x_raw*3 : x_raw;
    wire [11 : 0] font_y = VIDEO_VGA ? (y_raw*9)/4 : y_raw;
    wire hs0, vs0, de0, hs_active, vs_active;
    assign hs0 = VIDEO_VGA ? ~hs_active : hs_active;
    assign vs0 = VIDEO_VGA ? ~vs_active : vs_active;
    scope_video_timing #(.H_ACTIVE(VIDEO_VGA ? 640 : 1920),
                         .H_FRONT(VIDEO_VGA ? 16 : 88),
                         .H_SYNC(VIDEO_VGA ? 96 : 44),
                         .H_BACK(VIDEO_VGA ? 48 : 148),
                         .V_ACTIVE(VIDEO_VGA ? 480 : 1080),
                         .V_FRONT(VIDEO_VGA ? 10 : 4),
                         .V_SYNC(VIDEO_VGA ? 2 : 5),
                         .V_BACK(VIDEO_VGA ? 33 : 36))
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
            if (text_we && !pending && text_addr < 4800)
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
    wire plot = x >= 80 && x < 1040 && y >= 70 && y < 610;
    wire [9 : 0] wx = plot ? x - 80 : 0;
    wire [8 : 0] hx = plot ? (x - 80) / 6 : 0;
    wire [7 : 0] hy = plot ? (y - 70) / 6 : 0;
    reg [11 : 0] x0 = 0, y0 = 0;
    reg [19 : 0] hx_product = 0, hy_product = 0;
    reg [9 : 0] wx_address = 0;
    reg [12 : 0] char_address = 0;
    reg [4 : 0] glyph_row0 = 0;
    reg [4 : 0] glyph_bit0 = 0;
    reg glyph_valid0=0, glyph_valid1=0, glyph_valid2=0, glyph_valid3=0;
    always @(posedge pixel_clk) begin
        x0 <= x;
        y0 <= y;
        wx_address <= wx;
        char_address <= VIDEO_VGA ? (y_raw/16)*160+(x_raw>>2) : (y_raw/36)*160+x_raw/12;
        glyph_row0 <= (font_y%36>=6 && font_y%36<30) ? font_y%36-6 : 0;
        glyph_valid0 <= font_y%36>=6 && font_y%36<30;
        glyph_bit0 <= font_x%12;
        hx_product <= plot ? (x - 80) * 20'd683 : 20'd0;
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

    reg [7:0] hq=0;
    reg [15:0] cq=32,fq_hi=0,fq_mid=0,fq_lo=0;
    reg [11 : 0] x1 = 0, y1 = 0, x2 = 0, y2 = 0, x3 = 0, y3 = 0;
    reg [19 : 0] w2 = 0, w3 = 0;
    reg [7 : 0] h2 = 0, h3 = 0;
    reg [3 : 0] hsp = 0, vsp = 0, dep = 0;
    reg [4 : 0] row1 = 0;
    wire [13:0] font_address=(cq[8:0]>=32 ? cq[8:0]-9'd32 : 9'd0)*24+row1;
    reg [4 : 0] bit1 = 0, bit2 = 0;
    reg [47 : 0] font3 = 0;
    reg [4 : 0] bit3 = 0;
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
        glyph_valid1 <= glyph_valid0;
        glyph_valid2 <= glyph_valid1;
        glyph_valid3 <= glyph_valid2;
        bit1 <= glyph_bit0;
        fq_hi <= font_hi[font_address];
        fq_mid <= font_mid[font_address];
        fq_lo <= font_lo[font_address];
        bit2 <= bit1+(cq[9] ? 12 : 0);
        w2 <= VIDEO_VGA ? {pair_bottom, pair_top} : wq;
        h2 <= hq;
        font3 <= {fq_hi,fq_mid,fq_lo};
        bit3 <= bit2;
        w3 <= w2;
        h3 <= h2;
    end
    reg hs_q = 0, vs_q = 0, de_q = 0;
    assign hs = hs_q;
    assign vs = vs_q;
    assign de = de_q;
    wire in_plot = x3 >= 80 && x3 < 1040 && y3 >= 70 && y3 < 610;
    wire grid = (x3 == 80) || (x3 == 176) || (x3 == 272) || (x3 == 368) || (x3 == 464) ||
                (x3 == 560) || (x3 == 656) || (x3 == 752) || (x3 == 848) || (x3 == 944) || (x3 == 1039) || (y3 == 609) ||
                (y3 == 70) || (y3 == 124) || (y3 == 178) || (y3 == 232) || (y3 == 286) ||
                (y3 == 340) || (y3 == 394) || (y3 == 448) || (y3 == 502) || (y3 == 556);
    wire trace = in_plot && (VIDEO_VGA ? (y3 + 1 >= w3[9 : 0]) : (y3 >= w3[9 : 0])) &&
                 y3 <= w3[19 : 10] && meta_pix[31];
    wire [23 : 0] heat = h3 < 16    ? {8'd0, h3 << 3, 8'h40}
                         : h3 < 64  ? {8'd0, 8'hc0, h3 << 2}
                         : h3 < 128 ? {h3 << 1, 8'hff, 8'd0}
                                    : {8'hff, 8'hff - (h3 << 1), 8'd0};
    wire header_tab = 1'b0;
    wire selected_tab = (meta_pix[2 : 0] == 0 && x3 >= 240 && x3 < 328) ||
                        (meta_pix[2 : 0] == 1 && x3 >= 336 && x3 < 424) ||
                        (meta_pix[2 : 0] == 2 && x3 >= 432 && x3 < 520) ||
                        (meta_pix[2 : 0] == 3 && x3 >= 528 && x3 < 616) ||
                        (meta_pix[2 : 0] == 4 && x3 >= 624 && x3 < 712) ||
                        (meta_pix[2 : 0] == 5 && x3 >= 720 && x3 < 808) ||
                        (meta_pix[2 : 0] == 6 && x3 >= 816 && x3 < 904);
    wire card = x3 >= 1056 && x3 < 1264 &&
                ((y3 >= 72 && y3 < 192) || (y3 >= 204 && y3 < 300) || (y3 >= 312 && y3 < 432) ||
                 (y3 >= 444 && y3 < 610));
    wire card_edge = card && (x3 == 1056 || x3 == 1263 || y3 == 72 || y3 == 191 || y3 == 204 ||
                              y3 == 299 || y3 == 312 || y3 == 431 || y3 == 444 || y3 == 609);
    wire big_value =
             x3 >= 1056 && x3 < 1256 &&
             ((y3 >= 112 && y3 < 144) || (y3 >= 240 && y3 < 272) || (y3 >= 352 && y3 < 384));
    wire soft_trace = in_plot && meta_pix[31] && w3[19 : 10] >= 70 && y3 + 1 >= w3[9 : 0] &&
                      y3 <= w3[19 : 10] + 1;
    reg [23:0] base_color, text_color;
    wire [1:0] font_coverage=glyph_valid3 ? (font3 >> ((23-bit3)*2)) : 2'd0;
    function [7:0] blend_channel;
        input [7:0] background,foreground;
        input [1:0] coverage;
        reg [9:0] total;
        begin
            case(coverage)
                0:blend_channel=background;
                1:begin total=background*3+foreground;blend_channel=total>>2;end
                2:begin total=foreground*3+background;blend_channel=total>>2;end
                3:blend_channel=foreground;
            endcase
        end
    endfunction
    always @* begin
        base_color = 24'h101a29;
        if (y3 < 60 || y3 >= 630)
            base_color = 24'h111d2b;
        if (in_plot) begin
            base_color = grid ? 24'h25364b : 24'h0c1522;
            if ((x3 == 560 || y3 == 340) && (x3[3 : 0] < 8 && y3[3 : 0] < 8))
                base_color = 24'h415067;
            if (!meta_pix[16] && (meta_pix[2 : 0] == 1 || meta_pix[2 : 0] == 2)) begin
                if (meta_pix[31] && h3 != 0)
                    base_color = heat;
            end else begin
                if (soft_trace)
                    base_color = 24'h6b522c;
                if (trace)
                    base_color = meta_pix[2 : 0] == 3 ? 24'hb59aff : 24'hffce73;
            end
            if (x3 == 560 && y3 < 80 && meta_pix[2 : 0] != 3)
                base_color = 24'hf2a65a;
        end
        if (card)
            base_color = card_edge ? 24'h27374a : 24'h111e2c;
        if (x3 >= 1056 && x3 < 1059 &&
            ((y3 >= 80 && y3 < 192) || (y3 >= 200 && y3 < 304) || (y3 >= 312 && y3 < 416)))
            base_color = y3 < 200 ? 24'h61c8e0 : 24'hffce73;
        if (header_tab)
            base_color = selected_tab ? 24'h254354 : 24'h142333;
        if (header_tab && selected_tab && y3 == 33)
            base_color = 24'h61c8e0;
        if (x3 >= 1072 && x3 < 1264 && y3 >= 0 && y3 < 24)
            base_color = 24'h183b35;
        if (meta_pix[8] && y3 >= 61 && y3 < 69) base_color = 24'hd99336;
        if (y3 == 68 || y3 == 646)
            base_color = 24'h2b3c50;
        if (y3 == 646)
            base_color = 24'h375367;
        if (meta_pix[9] && !meta_pix[16] && x3>=128 && x3<1008 && y3>=96 && y3<552)
            base_color=24'h172b3d;
        text_color = 24'he1eaf5;
        if(y3<60)text_color=24'hecf4fc;
        if(y3<24 && x3<144)text_color=24'h68daca;
        if(x3>=1056 && (y3/24==3 || y3/24==6 || y3/24==9 || y3/24==13 || y3/24==19))
            text_color=24'h8fadc5;
        if(y3/24==27)text_color=24'hffce73;
        if(y3/24>=28)text_color=24'h9bb3c8;
    end
    always @(posedge pixel_clk) begin
        hs_q <= hsp[3];vs_q <= vsp[3];de_q <= dep[3];
        rgb <= {blend_channel(base_color[23:16],text_color[23:16],font_coverage),
                blend_channel(base_color[15:8],text_color[15:8],font_coverage),
                blend_channel(base_color[7:0],text_color[7:0],font_coverage)};
        if(pixel_rst)begin rgb<=0;hs_q<=0;vs_q<=0;de_q<=0;end
    end
endmodule
