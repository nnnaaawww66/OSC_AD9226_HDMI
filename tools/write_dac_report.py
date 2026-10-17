"""Write the human release report only after the current release gate passes."""
from pathlib import Path
import json

root=Path(__file__).resolve().parents[1]
a=json.loads((root/'docs/Acceptance.json').read_text(encoding='utf-8'))
assert a['version']=='4.0' and a['combined_hour']['status']=='HOUR_PASS'
s=a['combined_hour'];i=a['implementation'];identity=a['identity']
boot=next(f for f in a['artifacts']['boot']['files'] if f['name']=='BOOT.BIN')
report=f'''# Z7 LAB 4.0 · ADC / DAC904 交付记录

已在 `D:/Xilinx/Projects/OSC_ad9226_hdmi` 原工程完成独立 DAC904、中文 HDMI 与坐标、COM27 上位机及 QSPI 固化。实际 Flash 擦写和读回校验通过；用户断电切换中间 QSPI 跳线并重新上电后，未再下载 bit/ELF，已直接读回启动模式 1、正确版本和递增心跳。

本次数字实现和实板检查通过。模拟幅度、直流偏置、前端增益/带宽及外部接口余量没有用已校准仪器验证，资格与数字功能分别记录。完整机器记录见 `Acceptance.json`；原始证据见 `results/2026-10-17/dac_v4`。

## 交付功能

- ADC：真实 AD9226 四档 10/25/50/65MSa/s，七模式，无需重配置 FPGA。DSO/ROLL/MEM/SEG 显示时间与电平；FFT 为有效 Hz/dBFS；EYE 为 UI/电平；DPX 含命中强度。视窗、增益和中心变化时刻度同步更新。
- HDMI：1280×720@60Hz，原生 16×24 中英文点阵，中文菜单与详细状态；缺少有效周期时频率 N/A，显式 SIM 有持续告警。当前浮空输入不是内部固定 10kHz。
- DAC：独立固定 50MSa/s、32位 DDS、2048×14bit 双缓冲表；正弦、方波、三角、锯齿、直流、数学表达式及 CSV。完整 CRC 与 FPGA 读回后原子切换。ADC 的采样率、触发、来源、模式、校准及暂停不进入 DAC 数据链。
- 上位机：Windows 原生中文 PySide6，ADC / DAC / 诊断标签页；全局 HDMI 页面切换及停止 DAC；ADC 显示参数控制；DAC 预览、上传、参数 JSON、码值 CSV、日志导出；COM27 /115200 8N1，请求编号逐条确认。
- 启动：完整 FSBL + bit + ELF 的 BOOT.BIN，默认真实 ADC10MSa/s、DSO、RUN；DAC 保持中点。日常 QSPI 上电即用。配置 RAM/上位机 JSON 与启动镜像分别管理，不自动恢复此前开启的 DAC。

双方共用整板电源、50MHz板卡基准、系统启动、PS及管理/显示资源；全板复位会重启双方。停止 DAC 是保持数字中点8192，PD未接，不是高阻或物理掉电。HDMI/上位机 DAC 图是已配置数字表预览，不是模拟回读。

## 本次验证

正式封存 RTL 标识 `{identity['rtl_source']}`，ARM 标识 `{identity['firmware_source']}`。后续发布提交还含上位机、测试和文档；标识追溯到实际构建源，不把后来的文档提交冒充已烧录版本。

- 16项 XSim 全通过，包括 DAC 表读回、双缓冲、提交及锁存边沿；实际 C 分析与 NumPy、四组波形定义测试、C固件配置/CRC/读回故障检查通过。
- 实板四档 × 七模式、当前档位 DDR/DMA 自检、八段 CRC/时间戳、1000次模式切换通过。COM27 自定义表上传、错误参数/CRC拒绝、真实输出码与DDS相位核对，以及Qt控件到实际串口的完整操作通过。
- 新版本连续联合长测：串口观测 **{s['serial_duration_s']:.3f}s**，USB HDMI观测 **{s['hdmi_duration_s']:.3f}s**，共{s['observations']}次串口状态检查。ADC计数斜率{s['adc_measured_samples_per_s']:.2f}Sa/s，DAC{s['dac_measured_updates_per_s']:.2f}updates/s；PL视频{s['pl_video_measured_fps']:.5f}fps，USB采集{s['usb_capture_fps']:.3f}fps。DAC相位增量精确对应时钟增量，错误/OTR/丢样/UART丢失均为0。USB30fps与板上60Hz分别记录，静态输入不要求像素每帧改变。
- 五次同一封存版本的 JTAG 易失重载及 COM27 启动默认值检查通过；与用户实际 QSPI 断电启动分别记录。
- 从独立空目录重建 FPGA、ARM、FSBL、BOOT.BIN及封存通过；功能源文件与交付源逐文件比较。重建输出仅用于复现验证，未替换本次实板封存输出。
- 正式布局布线 WNS **{i['WNS_ns']:.3f}ns**，WHS **{i['WHS_ns']:.3f}ns**，TNS0；LUT{i['LUT']}/17600、FF{i['FF']}/35200、BRAM{i['BRAM36_equivalent']}/60、DSP{i['DSP']}/80。DAC14路均检查建立/保持；原始CDC159条Critical逐端点复核，未复核0；DRC无Error/Critical Warning，保留7条Warning及1条Advisory。

先前一次 USB DirectShow 采集停流时，板上计数和串口仍正常；该记录保存为中断，不计入成功长测，也未拼接为一小时。最终资格仅使用重新开始并连续完成的记录。旧 ADC 发布版的长测/ILA/截图保留为历史证据，不冒充本次 DAC 联合测试。

## 电压与 PRD 允许边界

ADC模块量程由用户给定 **±5V @50Ω**，初始换算10V/4095code、零点2047.5，并标明标称；平移中心不改变电压校准零点。DAC模块由用户给定标称 **5Vpp**，数字幅度以%FS控制，预览Vpp按实际表极值作标称估计。5Vpp零中心是±2.5V，但整体是否落在ADC±5V内，还取决于实际直流偏置、50Ω/高阻负载及模块电路。模块数字供电/电平转换未知项按TI门限说明保留，不能由5Vpp输出推断。

DPX/EYE使用PRD允许的160×90密度平面，事件丢弃/死区单独计数；MEM为有限1Mi点、SEG为八段16K，不宣称无死区环形DDR。EYE无参考锁定/CDR/BER，眼宽和抖动N/A；P2高级触发与CDR依原PRD允许延期，未伪列为完成。功耗1.904W为Vivado低置信度估计，不是实测温升。`ver qualification=BENCH_PENDING`是保留的固定字符串，最终资格以封存与本记录为准。

## 文件、备份与使用

原工程完整备份：`D:/Xilinx/Projects/OSC_ad9226_hdmi_backup_before_DAC_20261017`。原Flash完整16MiB读出备份：`backup/qspi_before_dac_20261017`；SHA256 `{a['flash']['original_backup_sha256']}`，设备CRC与本机CRC一致。

当前 BOOT.BIN：{boot['bytes']}bytes，SHA256 `{boot['sha256']}`。工程包含RTL/XDC/BD/SDK重建脚本、预构建bit/HDF/ELF/LTX/BOOT、原Flash备份、正式报告及本次实板证据。Windows上位机包含可执行文件和完整依赖目录，请整体解压后运行，不要只复制exe。

日常保持中间QSPI跳线；上位机选COM27连接。后续改动用 `build.ps1`，新解压目录用 `build.ps1 -Recreate`。按厂家流程，更新Flash先断电切到JTAG，再上电执行 `flash.ps1`，通过写入/校验后断电切回QSPI；`flash.ps1 -RestoreOriginal`恢复原Flash。详细按键、串口和坐标说明见 `User_Manual.md`、`DAC904_Extension.md`、`host/README.md`。
'''
(root/'docs/Delivery_Report.md').write_text(report,encoding='utf-8')
(root/'docs/Release_Notes.md').write_text('# Z7 LAB 4.0 发布说明\n\n独立DAC904、中文原生字体及全模式刻度、COM27上位机、完整QSPI启动与恢复已交付。正式验证、版本和边界见Delivery_Report.md与Acceptance.json；操作见User_Manual.md。\n',encoding='utf-8')
print('V4_REPORT_WRITTEN')
