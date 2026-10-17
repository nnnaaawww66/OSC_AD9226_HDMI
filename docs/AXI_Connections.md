# PS PL 连接与内存

PS7 M_AXI_GP0 → ctrl_bus → scope_0/s_axi（0x40000000，1MiB）及axi_dma_0/S_AXI_LITE（0x40400000，64KiB）。scope_0/m_axis → DMA S_AXIS_S2MM。DMA M_AXI_S2MM → hp_bus（必要协议/位宽转换）→PS S_AXI_HP0。各AXI时钟为PL产生的100MHz；PS FCLK0仍保留100MHz配置，但未把它作为视频或ADC采样许可。

IRQ concat In0=scope按键，In1=DMA S2MM；SDK生成的实际中断ID为61/62。GIC处理程序仅入队事件/应答状态；耗时FFT、栅格点准备和显示上传在主循环运行。

DDR实际控制参数取自厂家Hello World BD Tcl，完整来源SHA256在vendor_manifest.json。每次Validate Design后导出的recreate_scope_bd.tcl是重建依据；历史试验脚本不作为最终入口。

内存分区：

- 应用.text/.data/.bss/heap/stack：链接器限定0x00100000–0x07FFFFFF。
- DMA 1Mi×16-bit：0x10000000–0x101FFFFF，64字节对齐。
- 0x10200000–0x103FFFFF预留，当前不冒充已实现的连续乒乓DMA。
- SEG：从0x10400000开始，8×16384×2字节；至少保留到0x105FFFFF，元数据另有BSS索引。
- OCM诊断程序链接到ps7_ram_0，不访问DDR。其UART初始化来自同一已导出的PS7脚本。

DMA前flush/invalidate，DMA完成后invalidate再读；完成由IOC中断/标志验证，不能把初始IDLE当完成。原始16-bit格式[11:0]=规范化offset code、[12]=OTR、[15:13]=0。DMA测试恢复DDS初相并逐点比对完整1Mi序列，输出实际CRC和采集净荷速率；只在本次速率通过后开放MEM/SEG。

MEM是有限长度深记录；SEG是冻结BRAM块的DDR副本，二者不宣称65MSa/s连续无死区。所有停采死区和FIFO丢失有独立计数。

DMA调试计数分别反映不同位置：BYTES是ADC域源的累计生产字节，ACCEPT是最终AXIS接口累计成功的16bit拍数，包含绕过ADC FIFO的SYS压力源。混合自检后不可直接把BYTES与2×ACCEPT相等作为断言；单次传输的BTT、IOC、TLAST、丢弃增量及完整数据/CRC才是本次DMA闭环依据。

## 实板复位修正

旧版 proc_sys_reset 的 aux_reset_in 没有显式连接，2018.3 生成包装层将其默认接为 1，而 C_AUX_RESET_HIGH=1，使 peripheral_aresetn 一直保持低。这解释了视频独立输出而采集/AXI 不工作、CPU 卡在 PL_ID 读取的现象。现已通过 xlconstant reset_zero=0 显式连接 aux_reset_in 和 mb_debug_sys_rst，外部复位保持高有效。assert_bd_resets.tcl 在重建及综合之前检查连接、驱动常量和极性；负向测试会断开辅助复位并确认门禁拒绝。

OCM 末页 0x0002F000–0x0002FFFF 用于 JTAG 命令与诊断，OCM 恢复 ELF 的可用低 OCM 长度限定为 0x2F000。该区域不写入 Flash。
