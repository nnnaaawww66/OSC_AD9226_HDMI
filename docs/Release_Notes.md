# Z7 示波器：实板修复与新版 HDMI 界面

已直接修改并下载到 D:/Xilinx/Projects/OSC_ad9226_hdmi 中的原工程。当前使用 720p60、10MSa/s；实板通过 JTAG 调试，HDMI 画面直接从 USB3 Video 采集，无需操作桌面或连接 UART。

## 本次修复

原先只有视频正常，AXI 与采集一直处于复位：proc_sys_reset 辅助复位输入未连接，工具默认接为 1，而该端配置为高有效。现用 reset_zero=0 显式连接，并在重建/综合前检查驱动和极性；负向测试确认断开后构建门禁会拒绝。

同时修正下载脚本遇到 Already stopped 就终止的问题。program.ps1 现在会复位 PS、配置 PL、初始化 DDR、加载 ARM，并通过 OCM 心跳确认程序已进入主循环。只在 Vivado 加载 bit 不能替代 ARM 程序启动。

新增无需 UART 的 OCM JTAG 命令通道。主程序、恢复程序和调试页分区明确；JTAG 读写不暂停运行中的 CPU。

## 界面

顶部独立模式导航与运行/来源状态，右侧大号频率、峰峰值、RMS 卡片，下方集中显示触发、存储资格及故障。保留丢样、OTR、密度丢弃、FIFO 水位、采集死区、UI 刷新率与源码版本。

默认保留完整 16K 记录、8K 预触发，显示触发点附近 4K（40.96us/div），可用 TIME SPAN 改变。FFT 改为连续曲线，修复横轴整数溢出；DPX/EYE 不再叠加上一模式的旧波形。模式专属坐标说明与真实映射一致。

HDMI_DSO_live.png 等为真实板卡的 HDMI 抓图；ui_720p_rtl.png 为 RTL 仿真图，两类证据分别保留。

## 实际验证

- 最终 post-route：WNS 1.965ns、WHS 0.024ns；LUT 4133/17600、FF 6149/35200、BRAM 27.5/60、DSP 4/80。CDC 无 Unsafe/Unknown 端点；DRC 无 Error/Critical Warning，保留 7 条 Warning 和 1 条 Advisory。
- 12 组 RTL 回归通过；FFT/包络/测量/DDS 序列与 NumPy 金样本比对通过。新增 FFT 三档坐标标签和 OCM 命令序号/重复请求检查。
- 实板 ARM 主循环阶段 6、PL_ID=0x53434F50；七模式均通过 JTAG 切换并抓取 HDMI。
- 2MiB DDR 模式测试通过；完整 1Mi 点 DMA 与内部 DDS 序列逐样本比对通过，净荷约 19.999MB/s（10MSa/s × 16bit）。
- 实板连续 1000 次模式切换通过，视频持续输出；Normal 无边沿、Auto 超时、Single 保持/重武装、STOP 行为检查通过。
- 真实 ADC 当前输入 min=2037、max=2042，接近直流；OTR=0、丢样=0、errors=0。没有有效周期，因此频率显示 N/A，不能据此宣称模拟幅度/带宽已经标定。

原始证据位于 results/2026-10-17/hil。没有写 QSPI Flash。

## 使用

当前板卡保持 DSO / SIM 演示，方便直接看到波形。

- `./program.ps1`：以后通过 JTAG 一键配置 PL 并启动 ARM。
- `./jtag.ps1 status`、`./jtag.ps1 measure`：读取状态和测量有效性。
- `./jtag.ps1 adc source real`：切到真实 AD9226 输入；`./jtag.ps1 adc source sim` 返回内部测试。
- `./jtag.ps1 mode fft` 等：切换模式。
- `./jtag.ps1 selftest`：本次开机 DDR/DMA 自检，通过后开放 MEM/SEG。

双键操作、校准、全部命令见 User_Manual.md。在原工程运行 build.ps1 重建；新的解压目录运行 build.ps1 -Recreate。默认工具安装路径为 D:/Xilinx/Vivado/2018.3 与 SDK/2018.3。

## 保留的资格限制

25/50/65MSa/s 继续关闭；没有 130MB/s 连续 DDR 资格。MEM 是有限长度深记录，SEG 是八段记录，不宣称无死区。DPX/EYE 为 160×90 降级密度平面；EYE 无 CDR，眼宽/抖动保持 N/A。电压传输比例未标定，Vpp/RMS 保持 N/A。尚未完成已知信号源对照、一小时稳定性及多次物理冷启动，不能将本次数字链路通过等同于 PRD 全部验收。

bit 内嵌 RTL 提交为 2df3823f；交付提交、每个文件和压缩包的校验见 Release_Manifest.json 与 SHA256SUMS.txt。源码、BSP、bit/HDF/ELF、脚本、报告与实际 HDMI 抓图均已打包。
