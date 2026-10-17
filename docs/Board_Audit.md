# 板卡及接口审查

PROJECT: OSC_ad9226_hdmi / scope_z7lite

HARDWARE: xc7z010clg400-1 / Z7-Lite Rev1.1

BOARD_PROOF: 原厂 Z7-LITE_Rev1_1.pdf p2,p5,p7,p10,p11,p12,p13；原厂 Lab9 HDMI RTL/XDC；Hello World PS7 配置。

ADC_MODULE_VOLTAGE: USER_CONFIRMED_3V3_MODULE_SUPPLY。用户明确表示模块接 3.3V；未把此陈述误写为对芯片 AVDD、DRVDD、前端增益或输出电平的仪器实测。

ADC_CLK_DIRECTION: FPGA_TO_ADC；用户已确认 CLK 接 Y17 / JP1-16。

VIVADO_VERSION: Vivado 2018.3 / SW Build 2405991。

SDK_VERSION: SDK/XSCT 2018.3，实际 BSP 和 Cortex-A9 ELF 编译日志已保留。

JTAG_TARGET: 已识别 Digilent JTAG-HS2 201706300081 / xc7z010，已完成实际 bit + ELF 下载，OCM 启动阶段为 6，PL_ID=0x53434F50。证据位于 results/2026-10-17/hil。

UART_COM: 用户要求只使用 JTAG，本轮不连接 UART；命令和自检通过 OCM JTAG 通道完成。

GATE_G0: LIMITED。逻辑连线和用户供电/CLK 陈述已登记；模块电路、前端范围及实测偏斜未完成仪器验收。

NEXT_ACTION: 10MSa/s SIM 已实际运行；已验证 HDMI、DDR/DMA 自检、模式切换。继续真实信号/校准和长期稳定性验收。

BLOCKER: JTAG 与 USB HDMI 已闭环；仍缺已知信号源、ADC 模块传输系数、板级偏斜和模拟量仪器对照。

## 核查结论

- N18 是 PL 50MHz 参考；不是 PS 33.333333MHz 参考。
- Bank34 为 3.3V。HDMI 是 PL 直连 TMDS，没有 ADV7511。四对 P/N 与原厂示例和原理图一致。
- 两键 P16/T12 均低有效，未把其中一键占为硬复位。
- AD9226 的 AVDD、DRVDD 和模块电源接口是不同概念。芯片资料不能揭示未知模块上的稳压、升压、输入放大或 MODE 接法，故编码可切换，电压缩放默认无效。
- DDR 控制配置完整复用原厂 16-bit / 512MiB PS7 设置。PS7 导出的物理 DDR PAD 端口保留 32 DQ、4 DM、4 DQS 的接口宽度，匹配原厂包装层；这不把实际 16-bit 存储器改成 32-bit。
- 原厂配置中的 MT41J256M16 RE-125 时序基线与原理图 MT41K256M16 型号差异已保留在来源记录；未自造 DDR 训练/延迟参数，必须通过 DDR 实测后才开放存储模式。
- PS UART0 使用 MIO14/15，115200。不是 PL 软件串口。

原厂目录始终作为读取基准。源代码许可证/版权头保留在 hw/vendor；未改动厂家资料目录。
