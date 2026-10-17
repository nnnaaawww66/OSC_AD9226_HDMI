# Z7-Lite / AD9226 多模式示波器交付说明

已在 `D:/Xilinx/Projects/OSC_ad9226_hdmi` 原工程中完成七模式实现、启动修复、HDMI 界面改版和 JTAG 调试流程。正常启动默认 **真实 AD9226 / 10MSa/s / DSO**。10、25、50、65MSa/s 均已开放，分别经过输入时序检查和实板数字链路测试。详细资格与证据见 `Acceptance.json`；一小时测试结果以原始日志及机器分析为准。

## 固定 10kHz 的原因与修正

上一轮测试结束后仍选择内部 DDS 三角波 SIM，因此显示持续约 10kHz。现已改为默认真实 ADC；SIM 只能显式启用，并持续显示橙色告警。改变来源会清除旧测量、波形与密度，MEM/SEG 回放则保留所存记录的真实来源，避免把测试数据当作外部输入。

用户确认当前模拟输入浮空。实测原始码值约 2037～2044、OTR=0，当前没有有效周期，故频率显示 N/A；随机噪声和单脉冲也不能仅凭过零次数生成频率。输入电压未标定时 Vpp/RMS 显示 N/A，同时提供码值峰峰值及最小/最大值。

## 使用入口

- `./program.ps1`：校验九个发布文件的 SHA256，复位 PS、配置 PL、初始化 DDR、加载 ELF、验证启动阶段和心跳；自动执行 DDR/DMA 自检，再采集真实 ADC 的 MEM 记录。
- `./jtag.ps1 status`、`measure`、`clocks`、`video`：不连接 UART 即可检查当前状态。JTAG 通道不需要暂停 CPU。
- `./jtag.ps1 mode fft` 等：切换 DSO / DPX / EYE / FFT / ROLL / MEM / SEG。
- `./jtag.ps1 adc rate 65`：切采样率；切换后须重新 `selftest` 才开放 MEM/SEG。
- `./jtag.ps1 adc source sim`：显式开启内部测试；`adc source real` 返回 AD9226。
- 原目录 `./build.ps1`；新解压目录 `./build.ps1 -Recreate`。工具默认位于 `D:/Xilinx`，要求 Vivado/SDK 2018.3。

双键覆盖全部 21 项菜单。KEY1 选择、KEY2 调整、双键短按开关菜单、双键长按 RUN/STOP；详情及命令见 `User_Manual.md`。配置保存为易失 RAM，不写 Flash。

## 已完成的工程与验证

- **启动及界面**：修复辅助复位默认接高造成 AXI/采集永久复位；构建有连接/极性门禁及负向测试。界面采用七模式导航、运行/来源状态、大号测量卡片、网格与触发位置、底部诊断信息。实际 USB HDMI 抓图与 RTL 仿真图分开保存。
- **四档 ADC 时钟**：BUFGMUX_CTRL 无毛刺选择；50/65MHz 分离接收相位为 3.846ns。上一转换值的接收沿关系、AD9226 七拍流水线与 OTR 对齐有行为仿真；每档 13 路输入分别保留 setup/hold 检查。详见 `Clock_Plan.md`。
- **DSO / 触发 / ROLL**：16K 记录、8K 预触发、Auto/Normal/Single、STOP/重新武装；960 列 Min/Max 包络。ROLL 每 100000 个真实采样形成最值列，漏读列单独计数。
- **DPX / EYE / FFT**：共享 160×90 密度平面，命中 FIFO、同址旁路、饱和与衰减均有回归。EYE 支持已知 1～5Mb/s 的 2UI 折叠。FFT 支持 1024/2048/4096、Hann/Rect、boxcar 处理，实际 C 算法与 NumPy 比对。
- **DDR / MEM / SEG**：SYS 域压力源约 199.94MB/s，超过 143MB/s 门槛；65MSa/s 的完整 1Mi 点 DDS DMA 约 129.98MB/s，逐样本与相位序列比对通过。MEM 为有限 1Mi 点记录；SEG 为八个 16K 事件，CRC、样本序号时间戳及段间不重叠检查通过。
- **调试与回归**：15 组 RTL 回归、C/NumPy 金样本、实板四档/七模式、1000 次模式切换、五次热重启均通过。ADC/SYS/VIDEO 三个 ILA 已实际采集，验证样本序号、AXIS 背压/TLAST 和 HS/VS/DE。真实逐像素 RGB CRC32 与 Python zlib 金值一致。
- **可重建性**：在新的短路径目录中，从源码重建 Vivado 工程、IP、BSP 和两个 ELF，通过完整时序与发布校验；26 个硬件/固件源文件与实板发布源码逐文件一致。

实板最终 RTL 内嵌版本为 `a2c9e43f`，ARM 固件版本为 `7eea22be`；后续脚本和文档提交另见发布清单。禁止将干净重建中无 Git 元数据的 `00000000` 当作实板版本。

## 正式实现报告

WNS **1.914ns**、WHS **0.014ns**、TNS **0**；LUT **6997/17600**、FF **11441/35200**、BRAM **37.5/60**、DSP **4/80**。DRC 无 Error/Critical Warning，保留 7 条 Warning、1 条 Advisory。功耗估计 **1.873W / Low confidence**，并非电源仪表实测。

原始 CDC 报告有 **159 条 Critical**，分别为 UG472 定义的时钟选择控制端，以及厂商 ILA 已约束的内部配置路径；保留原始报告、68 个精确端点元组、厂商约束 SHA256 和负向门禁测试。**未复核 Critical=0**，不宣称原始 Critical 为零。四路 TMDS 串行输出保留 `no_output_delay` 提示，内部端点及所有 ADC 输入均受约束。

## 资格边界

- **PASS**：工程重建、数字时序门禁、七模式软件路径、四档数字测试、DDR 净荷与精确序列、触发语义、实际 HDMI、ILA、1000 次切换及热重启。持续运行结果单列在 `Acceptance.json` 与 `prd_completion/soak_analysis.json`。
- **LIMITED**：真实 ADC 已选通并观测浮空输入；尚未使用已知频率/幅度的外部参考，不能把内部 DDS 测试等同于模拟带宽、增益、板级接口偏斜或抗混叠验收。0～3ns 外部往返余量仍是工程假设。
- **LIMITED**：DPX/EYE 采用 PRD 允许的 160×90 降级；MEM 是有限记录，SEG 有明确死区；本轮按用户要求仅用 JTAG，物理 UART 及物理断电冷启动不列为已测。用户操作按键产生的七模式、RUN/STOP、ADC/SIM 切换已由日志观察并经用户确认；全部 21 项菜单仍以 RTL/固件回归为覆盖依据。
- **DISABLED**：未标定的电压读数；未锁定的 EYE 眼宽/抖动。高级脉宽/窗口触发、CDR、BER 属于 PRD 可延期的 P2 项，未实现。

原始证据主要位于 `results/2026-10-17/prd_completion`，完整时序/资源/时钟/功耗报告在其上一级。中断过的长测日志保留并明确命名，不并入成功的一小时记录。没有写入或擦除 QSPI Flash，也没有改动原厂资料目录。

持续运行采用两路独立观测：JTAG记录真实ADC样本序号、视频帧、锁、心跳和错误；USB HDMI直接读取实际画面，每秒检查固件头栏更新与SIM告警并周期保存原始帧。前者的视频计数约60Hz，后者的采集卡吞吐约30fps，两者不能混为同一指标。USB换口前的中断与换到根集线器后的完整记录分开保存。
