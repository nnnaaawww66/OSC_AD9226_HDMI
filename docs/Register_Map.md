# AXI Lite 寄存器

基址0x40000000，32-bit对齐，全字写；非法地址/字节写返回SLVERR。AW与W独立接收，B/R响应在背压期间保持。以下是偏移。

| 偏移 | 名称 | 方向与含义 |
|---|---|---|
| 0F8 | PIXEL_FRAME_CRC | RO，实际DE有效RGB888帧的IEEE CRC32 |
| 0F0/0F4 | VIDEO_PROFILE/SOURCE_SHA | RO，0=720p、1=640×480；32位RTL源码Git摘要 |
| 000/004 | ID/VERSION | RO，53434F50 / 00030000 |
| 008 | CTRL | RW，bit0 RUN，1 SIM，2 FALL，4:3 Auto/Normal/Single，6补码，19:8阈值，27:20迟滞；完整邮箱握手后采样域应用 |
| 00C | MODE | RW，0DSO/1DPX/2EYE/3FFT/4ROLL/5MEM/6SEG |
| 010 | ADC_RATE | RO实际Hz，写0/1/2/3选10/25/50/65；仅STOP可写；软件有独立实板资格门禁 |
| 014/018 | SAMPLE_COUNT | RO低/高32位，跨域一致快照 |
| 01C/020 | OTR/TRIGGER_COUNT | RO累计计数 |
| 024 | STATE | RO，0ready，3:1状态，4Auto超时，8release_busy，9cfg_busy，10ADC锁，11视频锁 |
| 028 | RECORD_START | RO环形起点 |
| 02C/030 | TRIGGER_INDEX | RO64位数字采样序号 |
| 034/038 | DEAD/VIDEO_FRAMES | RO，冻结死区样本数 / 真实视频消隐帧计数 |
| 03C | KEY_EVENT | RO高16位序号，15:4持续毫秒，2长按，1:0组合键；写完整事件应答IRQ |
| 040 | ERRORS | RO/W1C，0DMA丢失，1新OTR事件，2直方图丢失；清除后只有新事件重锁 |
| 044/048 | DMA_DROP/BYTES | RO，显式未交付点数 / 生产字节 |
| 04C/050 | DMA_LENGTH/START | RW点数；写START bit0启动，bit1清空FIFO并中止源；bit2+bit0启动SYS域递增码带宽测试 |
| 054/058 | DMA_ACCEPT/FLAGS | RO AXIS成功拍数 / bit13源active、12:0 FIFO水位 |
| 05C/060 | COMMIT/DISPLAY | 写提交后缓冲；RO bit0pending、1前bank |
| 064 | OWNER | bit0 PS接管；bit1菜单；6:2选项；bit7为当前显示记录的SIM来源。0允许自主PL包络构建 |
| 06C | RELEASE | 写脉冲释放冻结记录；Single仍保持，重新写配置才rearm |
| 070/074/078 | UI_CRC/HITS/HDROP | RW快照内容CRC、最近统计成功命中与显式丢弃 |
| 07C/080 | DMA_HWM/FALLBACK | RO DMA FIFO高水位 / PL包络状态 |
| 090/094 | ROLL_MINMAX/SEQ | RO低12位min、高12位max；连续全采样流每100000拍一个bin |
| 098/09C | ROLL_INDEX | RO64位bin末数字样本序号 |
| 0B0 | HIST_HIT | 写14位地址，底层调试命中入口 |
| 0B4/0B8 | HIST_BUSY/SCAN | RO bit0busy、7:1高水位；写bit0清零或bit1衰减，必须先idle |
| 0BC/0C0/0C4 | HIST_COMMIT/DROP/HWM | RO实际RMW命中总数、FIFO/非法地址丢弃和高水位 |
| 0D0/0D4/0D8 | RASTER_POINT/BUSY/DROP | 写x[7:0]、y[14:8]；RO忙及非法/忙时端点丢弃 |
| 0E0/0E4 | DMA_FIRST_INDEX | RO首个实际FIFO写入样本的64位数字序号 |
| 10000–1FFFF | FROZEN_RING | RO按时间顺序的16384点，每个32-bit位置承载一个16-bit点；未ready返回SLVERR |
| 20000–20EFF | WAVE_BACK | WO960列；低10位y_top，高10位y_bottom |
| 40000–4E0FF | HIST_BACK | WO160×90字节密度，单地址按32-bit间距写 |
| 80000–8707F | TEXT_BACK | WO160×45 ASCII字符 |
| C0000–CE0FF | HIST_READ | RO共享PL直方图，扫描/RMW忙时禁止读 |

0xF8为PL视频像素流实际CRC，覆盖有效区RGB。0x70的资产CRC覆盖文字、包络以及当前有效密度平面，不等于0xF8的视频像素CRC，也不等于采集卡经颜色转换后的图像CRC。静态字体和网格由版本与源文件SHA256标识。读取自由运行64位计数器应采用高/低/高重读；冻结触发元数据在释放前不变。
