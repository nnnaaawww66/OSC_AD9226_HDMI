# 可复现测试入口

硬件构建使用 Vivado/SDK 2018.3，路径默认 `D:/Xilinx`。本机测试环境为 Python 3.13.9、NumPy 2.3.5、Pillow 12.0.0、PyAV 18.0.0；C 金样本/界面测试使用 `C:/MinGW64/bin/gcc.exe`。前两项 Python 测试及 RTL 不连接板卡。

## 离线回归

在工程根目录执行，Python 可换为同等依赖环境中的解释器：

```powershell
$env:PATH = 'C:\MinGW64\bin;' + $env:PATH
& D:/Anaconda/python.exe sim/run_sim.py
& D:/Anaconda/python.exe tests/test_analysis.py
& D:/Anaconda/python.exe tests/render_ui.py
& D:/Anaconda/python.exe tests/render_vga.py
& D:/Xilinx/SDK/2018.3/bin/xsct.bat tests/check_unsigned_counter.tcl
& D:/Xilinx/SDK/2018.3/bin/xsct.bat tests/check_hil_cleanup.tcl
```

`run_sim.py` 不指定模块时运行全部 15 项。指定单项会覆盖 `simulation/summary.json`，正式封存前应保留全量结果。随机种子和金样本在源码中固定。UI 测试由实际 C 固件生成文字/包络，再由真实 RTL 渲染；RGB 字节 CRC 另由 Python zlib 比对。VGA 为离线回归，实际采集卡验证的是 720p。

`check_reset_gate.tcl` 需要 Vivado 项目，临时断开后恢复辅助复位连接且不保存错误设计；`check_cdc_gate.tcl` 检查正式原始 CDC 报告并注入两条未知路径，确认门禁拒绝。清理测试不连接 JTAG，注入的错误输出为预期场景，最终须有 `HIL_CLEANUP_TEST_PASS`。

## 实板测试

先运行 `program.ps1`。每次只运行一个会连接硬件的测试脚本，避免 OCM 单请求/应答通道发生竞争。以下测试会改变易失模式/采样配置，不写 Flash；本轮没有运行物理 UART 测试。

```powershell
& D:/Xilinx/SDK/2018.3/bin/xsct.bat tests/hil/jtag_acceptance.tcl 0
& D:/Xilinx/SDK/2018.3/bin/xsct.bat tests/hil/prd_completion.tcl
& D:/Xilinx/SDK/2018.3/bin/xsct.bat tests/hil/soak.tcl
& D:/Anaconda/python.exe tests/hil/analyze_soak.py
```

`prd_completion.tcl` 验证四档自检、七模式、八段 CRC/时间戳、配置真实速率恢复及 1000 次切换。SIM 用于精确数字金样本，最后恢复 REAL；失败也尝试恢复 REAL/DSO/Auto/RUN，恢复错误会保留。

`soak.tcl` 默认 3605 秒，初始选择 REAL / 65MSa/s / RUN，并进行自检及真实 MEM 采集。保持供电、JTAG 和来源/速率；切到 SIM 或其他速率会中止资格记录。RUN/STOP 和模式状态会进入原始日志；STOP 时间不冒充有效记录采集时间。分析必须看到完整 PASS 标记以及至少 3600000ms 的实际观测跨度，检查视频/原始 ADC 样本计数、心跳、锁、错误和丢样。中断记录另外命名，不能拼接成一小时。

## HDMI / ILA / 发布

关闭占用采集卡的相机应用后，直接读取命名设备，不截桌面：

```powershell
& D:/Anaconda/python.exe tests/hil/capture_hdmi.py --output results/2026-10-17/prd_completion/HDMI_current.png
& D:/Xilinx/Vivado/2018.3/bin/vivado.bat -mode batch -nojournal -source hw/scripts/capture_ila.tcl
& D:/Anaconda/python.exe tests/hil/analyze_ila.py
& D:/Anaconda/python.exe tests/write_acceptance.py
```

ILA 需要正式 `scope_top.bit` 和匹配 `scope_top.ltx`，会使用易失 DDR 压力源；不要与长测同时启动。源归属、物理模拟输入、仪器校准与数字自检分开记录。发布脚本绑定 HIL 中的 RTL 版本与正式文件校验，重建产生新版本后应重新完成对应实板测试，不能沿用旧记录宣称新版本通过。
