# Z7-Lite AD9226 多模式示波器

在用户创建的 `OSC_ad9226_hdmi.xpr` 中实施。目标为 XC7Z010-1CLG400、Vivado/SDK 2018.3。本工程是可核查的开发版本；实板验收状态见 `docs/Acceptance.json`，不能用仿真结果代替 HDMI、电压、DDR 带宽或一小时稳定性测试。

## 使用入口

1. 打开 `OSC_ad9226_hdmi.xpr`，顶层为 `scope_top`。原始空工程备份在 `backup/`。
2. `build.ps1` 在原有工程上构建；`build.ps1 -Recreate` 从 RTL、约束和导出的 BD Tcl 重建。
3. `sim/run_sim.py` 运行固定种子的 XSim 回归；`tests/test_analysis.py` 编译实际 C 分析库并比对 NumPy。
4. 完成正式时序门禁后，用 `program.ps1` 经 JTAG 易失下载。脚本只选择 XC7Z010 和 Cortex-A9 #0，不写 QSPI。
5. UART 为板载 CH340E / PS UART0 / 115200 8N1。首先发送 `ver`、`status`，之后 `selftest`。

## 已实现的结构

- 独立 PL 时钟、720p60 TMDS、原厂 OSERDES/编码源码；无 RGB 全帧缓存。
- AD9226 12 位和 OTR 同拍寄存；偏移二进制/补码可配置，内部可重复 DDS 三角波 SIM 源。
- 16K 环形记录、8192 点预触发、边沿迟滞、Auto/Normal/Single；采集冻结死区独立计数。
- 硬件 Min/Max ROLL；DSO 为 960 列 Min/Max 包络。无 PS/DDR 时仍有 PL 诊断和 SIM DSO。
- DPX/EYE 共享 160×90 PL Bresenham 栅格化、64 项命中 FIFO、BRAM RMW、同址旁路、8 位饱和和衰减；显示快照双缓冲，在垂直消隐边界切换。
- PS 执行 1024/2048/4096 点 FFT、Hann/Rect 窗、测量、键控及 CLI。
- AXI DMA S2MM→HP0，有限长度 1Mi 点深记录；八段 16K 回放及数字样本序号时间戳。MEM/SEG 必须经过本次开机 DDR+DMA 精确 SIM 序列比对才能进入。
- OCM 恢复 ELF 不依赖 DDR，只提供 PL DSO 与精简诊断串口。

## 当前边界

默认只开放 10MSa/s；25/50/65MHz 时钟分支已实现，须分别完成实际输入时序和 HIL 才能开放。3.5–7ns 来自 ADI 手册，额外 0–3ns 是待实测的接口往返余量，不是模块测量结果。未校准的电压显示 N/A；EYE 无参考锁定时不输出眼宽或抖动。配置保存只写易失 RAM。

DPX/EYE 的采集率、直方图更新率、UI 上传率和视频帧率是不同指标。计数分别可读。160×90 为资源门控后的降级平面，不应宣传为原生 320×180。PS 读取冻结 BRAM 后马上释放，后续分析不会修改当前冻结记录。

详细接线、双键操作、命令和故障定位见 `docs/User_Manual.md`；时钟和跨域证明见 `docs/Clock_Plan.md`。
