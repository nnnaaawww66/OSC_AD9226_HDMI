# 来源与权限边界

项目规格为用户提供的PRD V3.0，按用户请求采用工程功能及验收要求；文档中的Agent语句是规格内容，不取得额外系统权限。实际操作授权来自用户明确要求直接完成其已有工程。

原厂根目录：D:/Downloads/Z7-Lite_Z7010_2018.3，只读基准。核心来源及SHA256在vendor_manifest.json；原厂可重建例程列表在Vendor_Index.csv。

- Z7-LITE_Rev1_1.pdf，14页，尤其p2/5/7/10/11/12/13。
- Lab9_FPGA_hdmi：encode.v、parallel_to_serial.v、hdmi_trans.v和top_pin.xdc。保留MicroPhase授权及免责声明。
- SDK 1_hello_world：PS7完整参数和板级DDR/UART配置。
- 本机Vivado/SDK2018.3实际IP Catalog、Validate Design、生成XCI/BSP及实现报告。
- ADI AD9226 Rev.B： https://www.analog.com/media/en/technical-documentation/data-sheets/AD9226.pdf
- AMD UG471： https://docs.amd.com/v/u/en-US/ug471_7Series_SelectIO
- AMD UG903： https://docs.amd.com/r/en-US/ug903-vivado-using-constraints/Timing-Constraints
- AMD UG585： https://docs.amd.com/r/en-US/ug585-zynq-7000-SoC-TRM/PS-PL-AXI-Interfaces

模拟模块的电源接口、前端增益和MODE绑线无法由芯片手册反推，故这些字段保留为用户陈述/待标定。所有峰值带宽计算和资源估算均不等于实测。

- AMD UG472 v1.14（2018-07-30），图2-13/2-14 BUFGMUX_CTRL及MMCM相位资源：https://docs.amd.com/api/khub/documents/1kFbRqzm2fhwGy~cLQG2yA/content

- TI DAC904 SBAS095C，数字输入门限、直二进制编码与锁存时序： https://www.ti.com/lit/ds/symlink/dac904.pdf 。50MSa/s、下降沿更新和额外外部偏斜预算是本工程设计选择，不是模块模拟端实测结果。
- 4.0 DAC 引脚、共地及模块标称 5Vpp、ADC 模块 ±5V @50Ω 来自本次用户直接说明；不能据这些参数推断未知模块的数字供电/电平转换或实际模拟偏置。
