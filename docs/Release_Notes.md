# 2026-10-17 开发交付

本次是完成数字实现和 PC 验证的上板候选版，PRD G1–G9 的硬件门禁尚未通过。正式逐项状态与证据位于 Acceptance.json。

实际发布配置为 720p60、10MSa/s。Vivado 2018.3 post-route WNS 1.931ns、WHS 0.045ns；LUT 3884、FF 6150、BRAM 27.5/60、DSP 4/80。CDC 报告无 Unsafe/Unknown 端点；DRC 无 Error/Critical Warning。12 组 RTL 回归通过，C 分析库已与 NumPy 金样本比较。

bit 的内嵌 RTL 版本为 1aa430cb；后续只改 ARM 程序、测试、入口脚本与文档，交付 Git 提交另行记录。用 build_revision.txt 与 SHA256 清单识别具体产物，不应把后续 Git 提交号误当成该 bit 的内嵌版本。

## 限制和复现

- 25/50/65MSa/s 硬件及软件均关闭；全速探索报告保留在 results/2026-10-17/all_rates_exploration。不要打开资格掩码后直接宣称满速。
- DPX/EYE 为 160×90 的资源降级平面。EYE 无 CDR、无眼宽/抖动资格。
- MEM 为有限长度 1Mi 点，SEG 为八段冻结记录副本。DDR/DMA 本次开机自检通过才开放，不承诺连续无死区 DDR。
- 外部 ADC 模块电压增益未知，Vpp/RMS 默认 N/A。用户已确认模块接 3.3V 且 CLK 接 Y17，不能据此推算模拟量程。
- 未下载板卡、未写 Flash；最后探测到 CH340 COM5，但 JTAG 没有可连接目标。仿真界面 PNG 不是屏幕实拍。

现有工程直接打开 OSC_ad9226_hdmi.xpr。在新的解压目录运行 PowerShell `./build.ps1 -Recreate` 重建工程和 SDK；在原工程运行 `./build.ps1`。工具默认 D:/Xilinx/Vivado/2018.3 与 SDK/2018.3，可编辑脚本路径适配其他安装目录。构建脚本对时序、DRC、CDC、SDK 输出设门禁；SDK 生成 sdk_build.ok 才算成功。

连接板卡后运行 `./program.ps1`，只经 JTAG 易失下载。DDR 初始化失败时选 OCM 恢复程序；其通过标记只代表已启动，仍需 UART/HDMI 自检。UART 为 115200 8N1，先 `ver`、`status`、`selftest`，再使用真实信号。

完整串口回归：`python tests/hil/serial_acceptance.py --port COM5 --mode-cycles 1000 --soak-seconds 3600`。它会执行 DDR/DMA 自检再测试七模式，任何失败保存原始日志并退出，不能把 PC 主机模型结果替代此测试。实际模拟量、HDMI 兼容性、输入相位和仪器测试另行记录。
