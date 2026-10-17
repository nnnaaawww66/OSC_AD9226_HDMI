# 已修问题、复现与当前边界

## 已修问题

1. **HDMI 有网格、PS OFFLINE，AXI 读取卡住**：`proc_sys_reset/aux_reset_in` 浮置后生成值为高，永久保持外设复位。显式接零，检查极性；`tests/check_reset_gate.tcl` 会主动断开该连接，确认构建门禁拒绝后再恢复。下载必须包含 bit、PS7 初始化及 ELF。
2. **浮空输入仍固定约 10kHz**：测试结束遗留内部 SIM。默认改为 REAL；SIM 持续告警；切来源清除旧结果。`capture_sources.py` 保持同一 USB 采集流分别记录 SIM 与 REAL，并用 finally 恢复 REAL。频率对直流、噪声、单脉冲的无效判断见 C/NumPy 回归。
3. **高速接收时序错误地关联到新转换沿**：50/65MHz 提前接收的是上一外送周期的转换值。以实际输入功能建立两沿 setup 关系，hold 仍检查 3.846ns；13 路输入逐项核对，不设置 ADC 数据 false_path。`tb_adc_latency.sv` 检查七拍延迟和 OTR，`assert_adc_clocks.tcl` 检查每档 max/min 路径。
4. **用 ADC 最高速率本身测不到 DDR 余量**：增加独立 SYS 100MHz 递增码压力源，核对完整序列及 >=143MB/s；实际约 199.94MB/s。ADC DMA 自检另外核对完整 1Mi 点 DDS 相位序列。
5. **配置加载只改屏幕上的速率**：加载与菜单统一调用停止/握手/切时钟/稳定/读回流程，废弃旧记录及存储资格。实际 HIL 保存 10M 配置、切 25M、加载后读回物理 10M，回归通过。
6. **EYE 长时间序号乘法溢出**：先对 64bit 样本序号取 2UI 周期模，再乘码率。四档采样、1～5Mb/s、100ppm 偏差和大序号金样本覆盖。
7. **长测 PC 脚本在样本低字过 0x80000000 时误判倒退**：XSCT Tcl `%x` 产生有符号 32bit 结果；重组前用 `& 0xffffffff`。`tests/check_unsigned_counter.tcl` 覆盖 0x7fffffff、0x80000000、0xffffffff、进位至下一高字。此为观测脚本错误，不能据此修改 FPGA 正常的 64bit 计数器。
8. **测试存储记录被误当真实输入回放**：MEM/SEG 保存并显示各自的来源。`program.ps1` 自检后额外采一份 REAL MEM；纯压力测试不产生有效 MEM 记录。
9. **长时间运行后 PC 分段时间戳排序报 integer value too large**：SDK2018.3 的 Tcl `lsort -integer` 收窄为32bit；实际约2414亿的样本序号无法排序。改用支持大整数比较的回调，保持硬件64bit时间戳原值。`check_unsigned_counter.tcl` 可重现旧限制，并验证0、2^31、2^32、实际大序号及2^64-1；修复后最终八段真实ADC的CRC与时间戳检查通过。

## 保留的测试中断记录

`soak_counter_parse_first_attempt.log` 为上述 Tcl 解析问题；`soak_jtag_disconnect_attempt.log`、`soak_second_usb_disconnect_attempt.log` 为 USB JTAG 在 Windows 中消失后的观测中断；`soak_manual_source_change_attempt.log` 为用户确认的物理按键切到 SIM。它们均不计入成功长测，完整的一小时须由新的 `soak.log` 和分析记录独立证明。

第二次 USB 断开后直接采集的 `HDMI_JTAG_disconnected.png` 显示固件界面、视频和采集计数继续增长，断开前错误为0。上游原为 VID_05E3/PID_0610 USB Hub；用户换口后确认为 ROOT_HUB30 直连。重连后重新装载并开始新的完整长测，同时用独立 USB HDMI 流检查界面持续更新。此记录不把 USB 断开归因于已证实的 FPGA 错误，也不把多段观测拼接为连续一小时。

## 当前资格边界

- 模拟输入由用户确认为浮空。芯片手册无法给出未知模块前端的实际增益、偏移和允许输入范围；电压校准保持无效，不填假 Vpp/RMS。板级往返时延的 0～3ns 余量是工程假设，外部已知信号和接口裕量仍需仪器对照。
- DPX/EYE 采用 PRD 允许的 160×90；事件预算和命中丢弃明确可见，不承诺每个 65MSa/s 样本都参与密度栅格化。Auto 无边沿时的采集刷新率也不代表有触发输入时的最高波形率。
- MEM 是 1Mi 点有限记录，SEG 为八段 16K，有冻结/读取死区；并未实现无死区 DDR 环形流。DDR 模式测试和精确 DMA 成功后才开放当前档位的存储入口。
- 无参考锁定的 EYE 眼宽/抖动显示 N/A；P2 高级触发、CDR 和 BER 未实现。UART 按用户要求断开，功能接口保留；热重启与物理断电冷启动分开记载。
- 原始 CDC 159 条 Critical 均保留并逐端点复核；仅“未复核 Critical=0”。TMDS 四路串行输出不填虚构并行接收时序；功耗报告置信度为 Low。

## 快速排查顺序

先执行 `jtag.ps1 ver/status/clocks/video`，核对版本、来源、两组 MMCM 锁和帧数增长。再执行 `measure` 看原始码范围、OTR 与有效性。使用显式 SIM 区分数字链路与外部输入，测试后返回 REAL。存储异常先查 `selftest/dma/errors`；密度异常查 `dpx` 的命中、丢弃和高水位。若日志有错，保留原始序号、时间、版本和最短复现操作，再按模块回归；不用清零计数掩盖问题。
