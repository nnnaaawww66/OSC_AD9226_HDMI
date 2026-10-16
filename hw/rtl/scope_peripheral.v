`ifndef SCOPE_BUILD_SHA
`define SCOPE_BUILD_SHA 32'h00000000
`endif
`timescale 1ns / 1ps
module scope_peripheral
    #(parameter VIDEO_VGA = 0, ENABLE_RATE_SWITCH = 0)
    ((* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 s_axi_aclk CLK",
      X_INTERFACE_PARAMETER =
          "ASSOCIATED_BUSIF s_axi:m_axis, ASSOCIATED_RESET s_axi_aresetn, FREQ_HZ 100000000" *)
         input wire s_axi_aclk,
     (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 s_axi_aresetn RST",
      X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *) input wire s_axi_aresetn,
     input wire [19 : 0] s_axi_awaddr,
     input wire [2 : 0] s_axi_awprot,
     input wire s_axi_awvalid,
     output wire s_axi_awready,
     input wire [31 : 0] s_axi_wdata,
     input wire [3 : 0] s_axi_wstrb,
     input wire s_axi_wvalid,
     output wire s_axi_wready,
     output reg [1 : 0] s_axi_bresp = 0,
     output reg s_axi_bvalid = 0,
     input wire s_axi_bready,
     input wire [19 : 0] s_axi_araddr,
     input wire [2 : 0] s_axi_arprot,
     input wire s_axi_arvalid,
     output wire s_axi_arready,
     output reg [31 : 0] s_axi_rdata = 0,
     output reg [1 : 0] s_axi_rresp = 0,
     output reg s_axi_rvalid = 0,
     input wire s_axi_rready,
     output wire [15 : 0] m_axis_tdata,
     output wire [1 : 0] m_axis_tkeep,
     output wire m_axis_tvalid,
     input wire m_axis_tready,
     output wire m_axis_tlast,
     input wire adc_clk_in, pixel_clk,
     input wire video_locked, adc_locked,
     input wire [11 : 0] adc_data,
     input wire adc_otr,
     input wire [1 : 0] key_n,
     output wire [1 : 0] rate_sel,
     output wire [23 : 0] rgb,
     output wire hs, vs, de,
     output wire irq);

    reg hist_hit = 0, hist_clear = 0, hist_decay = 0;
    reg [13 : 0] hist_hit_addr = 0;
    reg raster_point = 0;
    reg [14 : 0] raster_xy = 0;
    wire raster_ready, raster_valid, raster_busy;
    wire [13 : 0] raster_address;
    wire [31 : 0] raster_drops;
    scope_raster raster(.clk(s_axi_aclk),
                        .rst(!s_axi_aresetn),
                        .clear(hist_clear | hist_decay),
                        .point_valid(raster_point),
                        .point_x(raster_xy[7 : 0]),
                        .point_y(raster_xy[14 : 8]),
                        .hit_ready(raster_ready && !hist_hit),
                        .hit_valid(raster_valid),
                        .hit_address(raster_address),
                        .busy(raster_busy),
                        .point_drops(raster_drops));

    wire hist_busy;
    wire [7 : 0] hist_read;
    wire [31 : 0] hist_committed, hist_dropped;
    wire [6 : 0] hist_hwm;
    scope_histogram hist_core(.clk(s_axi_aclk),
                              .rst(!s_axi_aresetn),
                              .hit(hist_hit || (raster_valid && raster_ready)),
                              .hit_addr(hist_hit ? hist_hit_addr : raster_address),
                              .clear(hist_clear),
                              .decay(hist_decay),
                              .read_addr(ra_reg[15 : 2]),
                              .read_data(hist_read),
                              .busy(hist_busy),
                              .committed(hist_committed),
                              .dropped(hist_dropped),
                              .high_water(hist_hwm),
                              .hit_ready(raster_ready));
    reg [1 : 0] rate_requested = 0;
    assign rate_sel = ENABLE_RATE_SWITCH ? rate_requested : 2'b00;
    wire clk = s_axi_aclk, rst = !s_axi_aresetn;
    wire adc_rst, pixel_rst;
    reset_sync arst(.clk(adc_clk_in),
                    .arst(rst),
                    .rst(adc_rst));
    reset_sync prst(.clk(pixel_clk),
                    .arst(!video_locked),
                    .rst(pixel_rst));
    reg fb_valid = 0;
    reg [11 : 0] fb_lo_latched = 0, fb_hi_latched = 0;
    reg [21 : 0] fb_lo_product = 0, fb_hi_product = 0;
    reg [9 : 0] fb_out_column = 0, fb_top_latched = 0, fb_bottom_latched = 0;
    reg fb_last_column = 0;

    reg [31 : 0] otr_seen = 0, drop_seen = 0, hist_drop_seen = 0;
    reg [31 : 0] config_reg = 32'h00880003, mode_reg = 0, error_flags = 0, owner = 0, crc_reg = 0,
                 hits_reg = 0, hist_drop_reg = 0;
    reg config_send = 0, release_send = 0;
    wire config_busy, release_busy;
    wire [31 : 0] adc_cfg;
    wire cfg_valid;
    scope_mailbox cfg_mb(.sclk(clk),
                         .srst(rst),
                         .sdata(config_reg),
                         .send(config_send),
                         .busy(config_busy),
                         .dclk(adc_clk_in),
                         .drst(adc_rst),
                         .ddata(adc_cfg),
                         .valid(cfg_valid));
    wire release_record, release_data;
    scope_mailbox #(.WIDTH(1))
        rel_mb(.sclk(clk),
               .srst(rst),
               .sdata(1'b1),
               .send(release_send),
               .busy(release_busy),
               .dclk(adc_clk_in),
               .drst(adc_rst),
               .ddata(release_data),
               .valid(release_record));
    reg sim_mode = 1, twos_comp = 0;
    always @(posedge adc_clk_in)
        if (adc_rst) begin
            sim_mode <= 1;
            twos_comp <= 0;
        end else if (cfg_valid) begin
            sim_mode <= adc_cfg[1];
            twos_comp <= adc_cfg[6];
        end
    (* IOB = "TRUE" *) reg [11 : 0] adc_q = 0;
    (* IOB = "TRUE" *) reg otr_q = 0;
    reg [23 : 0] sim_phase = 0;
    wire [11 : 0] sim_triangle = sim_phase[23] ? ~sim_phase[22 : 11] : sim_phase[22 : 11];
    always @(posedge adc_clk_in) begin
        adc_q <= adc_data;
        otr_q <= adc_otr;
        sim_phase <= sim_phase + 24'd16777;
    end
    wire[11 : 0] sample =
        sim_mode ? sim_triangle : (twos_comp ? {~adc_q[11], adc_q[10 : 0]} : adc_q);
    wire otr = sim_mode ? 1'b0 : otr_q;
    wire [13 : 0] waddr, start_addr, trig_addr;
    wire [15 : 0] wdata;
    wire wen, ready, auto_trig;
    wire [63 : 0] sample_count, trig_index;
    wire [31 : 0] otr_count, trig_count, dead_count;
    wire [2 : 0] cap_state;
    scope_capture capture(.clk(adc_clk_in),
                          .rst(adc_rst),
                          .sample(sample),
                          .otr(otr),
                          .config_word(adc_cfg),
                          .cfg_valid(cfg_valid),
                          .release_record(release_record),
                          .wr_addr(waddr),
                          .wr_data(wdata),
                          .wr_en(wen),
                          .ready(ready),
                          .record_start(start_addr),
                          .trigger_addr(trig_addr),
                          .sample_count(sample_count),
                          .otr_count(otr_count),
                          .trigger_count(trig_count),
                          .trigger_index(trig_index),
                          .auto_trigger(auto_trig),
                          .state(cap_state),
                          .dead_count(dead_count));
    (* ram_style = "block" *) reg [15 : 0] ring[0 : 16383];
    always @(posedge adc_clk_in)
        if (wen)
            ring[waddr] <= wdata;

    wire roll_valid;
    wire [119 : 0] roll_data;
    wire roll_busy, roll_bus_valid;
    wire [119 : 0] roll_status;
    scope_roll roll(.clk(adc_clk_in),
                    .rst(adc_rst),
                    .sample(sample),
                    .index(sample_count),
                    .valid(roll_valid),
                    .data(roll_data));
    scope_mailbox #(.WIDTH(120))
        roll_mb(.sclk(adc_clk_in),
                .srst(adc_rst),
                .sdata(roll_data),
                .send(roll_valid && !roll_busy),
                .busy(roll_busy),
                .dclk(clk),
                .drst(rst),
                .ddata(roll_status),
                .valid(roll_bus_valid));
    reg [7 : 0] status_timer = 0;
    always @(posedge adc_clk_in)
        status_timer <= status_timer + 1;
    wire status_busy, status_valid;
    wire [287 : 0] status_bus;
    // 288b coherent status snapshot. Payload only captured after request synchronization.
    scope_mailbox #(.WIDTH(288))
        status_mb(.sclk(adc_clk_in),
                  .srst(adc_rst),
                  .sdata({20'b0, auto_trig, cap_state, ready, 3'b0, start_addr, trig_addr,
                          dead_count, trig_index, trig_count, otr_count, sample_count}),
                  .send(status_timer == 0 && !status_busy),
                  .busy(status_busy),
                  .dclk(clk),
                  .drst(rst),
                  .ddata(status_bus),
                  .valid(status_valid));
    wire [63 : 0] cnt_s = status_bus[63 : 0];
    wire [31 : 0] otr_s = status_bus[95 : 64], trig_s = status_bus[127 : 96];
    wire [63 : 0] ti_s = status_bus[191 : 128];
    wire [31 : 0] dead_s = status_bus[223 : 192];
    wire [13 : 0] ta_s = status_bus[237 : 224], sa_s = status_bus[251 : 238];
    wire ready_s = status_bus[255];
    wire [2 : 0] state_s = status_bus[258 : 256];
    wire auto_s = status_bus[259];
    wire [31 : 0] key_event;
    scope_keys keys(.clk(clk),
                    .rst(rst),
                    .key_n(key_n),
                    .event_word(key_event));
    reg [15 : 0] key_ack = 0;
    assign irq = key_event[31 : 16] != key_ack;
    reg dma_start = 0, dma_flush = 0;
    reg [31 : 0] dma_count = 1048576;
    wire [63 : 0] dma_first;
    wire [31 : 0] dma_drop, dma_prod;
    wire dma_active;
    wire [12 : 0] fifo_level;
    scope_dma_stream dma_stream(.adc_clk(adc_clk_in),
                                .adc_rst(adc_rst),
                                .sample({3'b0, otr, sample}),
                                .start(dma_start),
                                .count(dma_count),
                                .bus_clk(clk),
                                .bus_rst(rst),
                                .m_axis_tdata(m_axis_tdata),
                                .m_axis_tkeep(m_axis_tkeep),
                                .m_axis_tvalid(m_axis_tvalid),
                                .m_axis_tready(m_axis_tready),
                                .m_axis_tlast(m_axis_tlast),
                                .dropped(dma_drop),
                                .produced(dma_prod),
                                .active(dma_active),
                                .fifo_level(fifo_level),
                                .flush(dma_flush),
                                .sample_index(sample_count),
                                .first_index(dma_first));
    wire dma_stat_busy, dma_stat_valid;
    wire [128 : 0] dma_status;
    scope_mailbox #(.WIDTH(129))
        dma_stat(.sclk(adc_clk_in),
                 .srst(adc_rst),
                 .sdata({dma_first, dma_active, dma_prod, dma_drop}),
                 .send(status_timer == 64 && !dma_stat_busy),
                 .busy(dma_stat_busy),
                 .dclk(clk),
                 .drst(rst),
                 .ddata(dma_status),
                 .valid(dma_stat_valid));
    reg [31 : 0] dma_accepted = 0;
    reg [12 : 0] fifo_hwm = 0;
    always @(posedge clk)
        if (rst) begin
            dma_accepted <= 0;
            fifo_hwm <= 0;
        end else begin
            if (m_axis_tvalid && m_axis_tready)
                dma_accepted <= dma_accepted + 1;
            if (fifo_level > fifo_hwm)
                fifo_hwm <= fifo_level;
        end
    reg wave_we = 0, hist_we = 0, text_we = 0, commit = 0;
    reg [9 : 0] wave_addr = 0;
    reg [19 : 0] wave_data = 0;
    reg [15 : 0] hist_addr = 0;
    reg [7 : 0] hist_data = 0, text_data = 0;
    reg [12 : 0] text_addr = 0;
    wire display_pending, front_bank;
    wire [31 : 0] video_frames;
    wire [31 : 0] frame_meta = {owner[0] | fb_valid, 22'b0,  config_reg[1],
                                config_reg[0],       auto_s, 3'b0,
                                mode_reg[2 : 0]} |
                               ((owner & 32'h7e) << 8);
    scope_display #(.VIDEO_VGA(VIDEO_VGA))
        display(.sys_clk(clk),
                .sys_rst(rst | !video_locked),
                .pixel_clk(pixel_clk),
                .pixel_rst(pixel_rst),
                .wave_we(wave_we),
                .wave_addr(wave_addr),
                .wave_data(wave_data),
                .hist_we(hist_we),
                .hist_addr(hist_addr),
                .hist_data(hist_data),
                .text_we(text_we),
                .text_addr(text_addr),
                .text_data(text_data),
                .commit(commit),
                .meta(frame_meta),
                .pending(display_pending),
                .frame_count(video_frames),
                .hs(hs),
                .vs(vs),
                .de(de),
                .rgb(rgb),
                .front_bank(front_bank));
    wire video_mb_busy, video_valid;
    wire [31 : 0] frames_s;
    scope_mailbox frame_mb(.sclk(pixel_clk),
                           .srst(pixel_rst),
                           .sdata(video_frames),
                           .send(!video_mb_busy),
                           .busy(video_mb_busy),
                           .dclk(clk),
                           .drst(rst | !video_locked),
                           .ddata(frames_s),
                           .valid(video_valid));
    // Read address and write data are independently accepted; responses persist under backpressure.
    reg aw_hold = 0, w_hold = 0;
    reg [19 : 0] aw_reg = 0;
    reg [31 : 0] wd_reg = 0;
    reg [3 : 0] ws_reg = 0;
    assign s_axi_awready = !aw_hold && !s_axi_bvalid;
    assign s_axi_wready = !w_hold && !s_axi_bvalid;
    reg [1 : 0] read_state = 0;
    reg [19 : 0] ra_reg = 0;
    reg [15 : 0] ring_q = 0;
    // Autonomous PL envelope builder runs without PS firmware or initialized DDR.
    reg [3 : 0] fb_state = 0;
    reg [13 : 0] fb_index = 0;
    reg [14 : 0] fb_phase = 0;
    reg [9 : 0] fb_column = 0;
    reg [11 : 0] fb_min = 4095, fb_max = 0;
    reg [31 : 0] fb_trigger = 0;
    wire [11 : 0] fb_value = ring_q[11 : 0];
    wire [11 : 0] fb_lo = fb_value < fb_min ? fb_value : fb_min,
                  fb_hi = fb_value > fb_max ? fb_value : fb_max;
    wire [9 : 0] fb_top = 609 - ((fb_hi * 539) >> 12), fb_bottom = 609 - ((fb_lo * 539) >> 12);

    wire [13 : 0] read_index = sa_s + ra_reg[15 : 2];
    assign s_axi_arready = read_state == 0 && !s_axi_rvalid;
    always @(posedge clk) begin
        ring_q <= ring[owner[0] ? read_index : sa_s + fb_index];
        wave_we <= 0;
        hist_we <= 0;
        text_we <= 0;
        commit <= 0;
        config_send <= 0;
        release_send <= 0;
        dma_start <= 0;
        dma_flush <= 0;
        hist_hit <= 0;
        raster_point <= 0;
        hist_clear <= 0;
        hist_decay <= 0;
        if (rst) begin
            aw_hold <= 0;
            w_hold <= 0;
            s_axi_bvalid <= 0;
            s_axi_rvalid <= 0;
            read_state <= 0;
            config_reg <= 32'h00880003;
            mode_reg <= 0;
            owner <= 0;
            rate_requested <= 0;
            error_flags <= 0;
            key_ack <= 0;
            fb_state <= 0;
            fb_valid <= 0;
            fb_trigger <= 0;
            otr_seen <= 0;
            drop_seen <= 0;
            hist_drop_seen <= 0;
        end else begin

            if (!owner[0])
                case (fb_state)
                    0:
                        if (ready_s && trig_s != fb_trigger && !display_pending) begin
                            fb_trigger <= trig_s;
                            fb_index <= 0;
                            fb_phase <= 0;
                            fb_column <= 0;
                            fb_min <= 4095;
                            fb_max <= 0;
                            fb_state <= 1;
                        end
                    1:
                        fb_state <= 2;
                    2:
                        fb_state <= 3;
                    3: begin
                        if (fb_phase + 960 >= 16384 || fb_index == 16383) begin
                            fb_lo_latched <= fb_lo;
                            fb_hi_latched <= fb_hi;
                            fb_out_column <= fb_column;
                            fb_last_column <= fb_index == 16383;
                            fb_column <= fb_column + 1;
                            fb_phase <= fb_phase + 960 - 16384;
                            fb_min <= 4095;
                            fb_max <= 0;
                        end else begin
                            fb_min <= fb_lo;
                            fb_max <= fb_hi;
                            fb_phase <= fb_phase + 960;
                        end
                        fb_index <= fb_index + 1;
                        if (fb_phase + 960 >= 16384 || fb_index == 16383)
                            fb_state <= 7;
                        else
                            fb_state <= 1;
                    end
                    7: begin
                        fb_lo_product <= fb_lo_latched * 539;
                        fb_hi_product <= fb_hi_latched * 539;
                        fb_state <= 8;
                    end
                    8: begin
                        fb_top_latched <= 609 - (fb_hi_product >> 12);
                        fb_bottom_latched <= 609 - (fb_lo_product >> 12);
                        fb_state <= 9;
                    end
                    9: begin
                        wave_we <= 1;
                        wave_addr <= fb_out_column;
                        wave_data <= {fb_bottom_latched, fb_top_latched};
                        fb_state <= fb_last_column ? 4 : 1;
                    end
                    4: begin
                        fb_valid <= 1;
                        fb_state <= 5;
                    end
                    5: begin
                        commit <= 1;
                        fb_state <= 6;
                    end
                    6:
                        if (!display_pending && !release_busy) begin
                            release_send <= 1;
                            fb_state <= 0;
                        end
                    default:
                        fb_state <= 0;
                endcase
            if (s_axi_awready && s_axi_awvalid) begin
                aw_hold <= 1;
                aw_reg <= s_axi_awaddr;
            end
            if (s_axi_wready && s_axi_wvalid) begin
                w_hold <= 1;
                wd_reg <= s_axi_wdata;
                ws_reg <= s_axi_wstrb;
            end
            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 0;
            if (aw_hold && w_hold && !s_axi_bvalid) begin
                aw_hold <= 0;
                w_hold <= 0;
                s_axi_bvalid <= 1;
                s_axi_bresp <= 0;
                if (aw_reg[1 : 0] != 0 || ws_reg != 4'hf)
                    s_axi_bresp <= 2'b10;
                else if (aw_reg >= 20'h20000 && aw_reg < 20'h20f00) begin
                    if (display_pending)
                        s_axi_bresp <= 2;
                    else begin
                        wave_we <= 1;
                        wave_addr <= aw_reg[11 : 2];
                        wave_data <= wd_reg[19 : 0];
                    end
                end else if (aw_reg >= 20'h40000 && aw_reg < 20'h4e100) begin
                    if (display_pending)
                        s_axi_bresp <= 2;
                    else begin
                        hist_we <= 1;
                        hist_addr <= (aw_reg - 20'h40000) >> 2;
                        hist_data <= wd_reg[7 : 0];
                    end
                end else if (aw_reg >= 20'h80000 && aw_reg < 20'h87080) begin
                    if (display_pending)
                        s_axi_bresp <= 2;
                    else begin
                        text_we <= 1;
                        text_addr <= (aw_reg - 20'h80000) >> 2;
                        text_data <= wd_reg[7 : 0];
                    end
                end else
                    case (aw_reg)
                        'h08:
                            if (config_busy)
                                s_axi_bresp <= 2;
                            else begin
                                config_reg <= wd_reg;
                                config_send <= 1;
                            end
                        'h0c:
                            mode_reg <= wd_reg;
                        'h10: begin
                            // Physical rate changes are only legal while STOPped, after explicit
                            // host qualification.
                            if (config_reg[0] || wd_reg > 3 || (!ENABLE_RATE_SWITCH && wd_reg != 0))
                                s_axi_bresp <= 2;
                            else
                                rate_requested <= wd_reg[1 : 0];
                        end
                        'h3c:
                            key_ack <= wd_reg[31 : 16];
                        'h40:
                            error_flags <= error_flags & ~wd_reg;
                        'h4c:
                            dma_count <= wd_reg;
                        'h50:
                            if (wd_reg[1])
                                dma_flush <= 1;
                            else if (dma_status[64])
                                s_axi_bresp <= 2;
                            else
                                dma_start <= 1;
                        'h5c:
                            if (display_pending)
                                s_axi_bresp <= 2;
                            else
                                commit <= 1;
                        'h64: begin
                            owner <= wd_reg;
                            fb_state <= 0;
                        end
                        'h6c:
                            if (!release_busy)
                                release_send <= 1;
                            else
                                s_axi_bresp <= 2;
                        'h70:
                            crc_reg <= wd_reg;
                        'h74:
                            hits_reg <= wd_reg;

                        'h78:
                            hist_drop_reg <= wd_reg;
                        'hb0: begin
                            hist_hit <= 1;
                            hist_hit_addr <= wd_reg[13 : 0];
                        end
                        'hd0:
                            if (raster_busy)
                                s_axi_bresp <= 2;
                            else begin
                                raster_point <= 1;
                                raster_xy <= wd_reg[14 : 0];
                            end
                        'hb8:
                            if (hist_busy)
                                s_axi_bresp <= 2;
                            else begin
                                hist_clear <= wd_reg[0];
                                hist_decay <= wd_reg[1];
                            end
                        default:
                            s_axi_bresp <= 2;
                    endcase
            end
            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 0;
            if (s_axi_arready && s_axi_arvalid) begin
                ra_reg <= s_axi_araddr;
                read_state <= 1;
            end
            if (read_state == 1)
                read_state <= 2;
            if (read_state == 2) begin
                read_state <= 0;
                s_axi_rvalid <= 1;
                s_axi_rresp <= 0;
                s_axi_rdata <= 0;
                if (ra_reg[1 : 0] != 0)
                    s_axi_rresp <= 2;
                else if (ra_reg >= 20'h10000 && ra_reg < 20'h20000) begin
                    if (!ready_s)
                        s_axi_rresp <= 2;
                    else
                        s_axi_rdata <= {16'b0, ring_q};
                end else if (ra_reg >= 20'hc0000 && ra_reg < 20'hce100) begin
                    if (hist_busy)
                        s_axi_rresp <= 2;
                    else
                        s_axi_rdata <= {24'b0, hist_read};
                end else
                    case (ra_reg)
                        'h00:
                            s_axi_rdata <= 32'h53434f50;
                        'h04:
                            s_axi_rdata <= 32'h00030000;
                        'h08:
                            s_axi_rdata <= config_reg;
                        'h0c:
                            s_axi_rdata <= mode_reg;
                        'h10:
                            case (rate_sel)
                                0:
                                    s_axi_rdata <= 10000000;
                                1:
                                    s_axi_rdata <= 25000000;
                                2:
                                    s_axi_rdata <= 50000000;
                                3:
                                    s_axi_rdata <= 65000000;
                            endcase
                        'h14:
                            s_axi_rdata <= cnt_s[31 : 0];
                        'h18:
                            s_axi_rdata <= cnt_s[63 : 32];
                        'h1c:
                            s_axi_rdata <= otr_s;
                        'h20:
                            s_axi_rdata <= trig_s;
                        'h24:
                            s_axi_rdata <=
                                {20'b0, video_locked, adc_locked, config_busy, release_busy,
                                 3'b0,  auto_s,       state_s,    ready_s};
                        'h28:
                            s_axi_rdata <= {18'b0, sa_s};
                        'h2c:
                            s_axi_rdata <= ti_s[31 : 0];
                        'h30:
                            s_axi_rdata <= ti_s[63 : 32];
                        'h34:
                            s_axi_rdata <= dead_s;
                        'h38:
                            s_axi_rdata <= frames_s;
                        'h3c:
                            s_axi_rdata <= key_event;
                        'h40:
                            s_axi_rdata <= error_flags;
                        'h44:
                            s_axi_rdata <= dma_status[31 : 0];
                        'h48:
                            s_axi_rdata <= dma_status[63 : 32] * 2;
                        'h4c:
                            s_axi_rdata <= dma_count;
                        'h54:
                            s_axi_rdata <= dma_accepted;
                        'h58:
                            s_axi_rdata <= {18'b0, dma_status[64], fifo_level};
                        'h60:
                            s_axi_rdata <= {30'b0, front_bank, display_pending};
                        'h64:
                            s_axi_rdata <= owner;

                        'h80:
                            s_axi_rdata <= fb_state;
                        'h90:
                            s_axi_rdata <= {8'b0, roll_status[23 : 0]};
                        'h94:
                            s_axi_rdata <= roll_status[119 : 88];
                        'h98:
                            s_axi_rdata <= roll_status[55 : 24];
                        'h9c:
                            s_axi_rdata <= roll_status[87 : 56];
                        'hb4:
                            s_axi_rdata <= {24'b0, hist_hwm, hist_busy};
                        'hbc:
                            s_axi_rdata <= hist_committed;
                        'hc0:
                            s_axi_rdata <= hist_dropped;
                        'hc4:
                            s_axi_rdata <= hist_hwm;
                        'hd4:
                            s_axi_rdata <= {31'b0, raster_busy};
                        'hd8:
                            s_axi_rdata <= raster_drops;
                        'he0:
                            s_axi_rdata <= dma_status[96 : 65];
                        'he4:
                            s_axi_rdata <= dma_status[128 : 97];
                        'hf0:
                            s_axi_rdata <= VIDEO_VGA;
                        'hf4:
                            s_axi_rdata <= `SCOPE_BUILD_SHA;
                        'h70:
                            s_axi_rdata <= crc_reg;
                        'h74:
                            s_axi_rdata <= hits_reg;
                        'h78:
                            s_axi_rdata <= hist_drop_reg;
                        'h7c:
                            s_axi_rdata <= fifo_hwm;
                        default:
                            s_axi_rresp <= 2;
                    endcase
            end
            if (dma_status[31 : 0] != drop_seen) begin
                error_flags[0] <= 1;
                drop_seen <= dma_status[31 : 0];
            end
            if (hist_dropped != hist_drop_seen) begin
                error_flags[2] <= 1;
                hist_drop_seen <= hist_dropped;
            end
            if (otr_s != otr_seen) begin
                error_flags[1] <= 1;
                otr_seen <= otr_s;
            end
        end
    end
endmodule
