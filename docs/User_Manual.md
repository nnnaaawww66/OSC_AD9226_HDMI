# 操作与调试说明

## 4.0 发布版：日常使用

本节和 `DAC904_Extension.md` 是 ADC/DAC 4.0 的使用入口。本文后半部分保留底层调试说明；旧版仅 JTAG、未写 Flash、电压未设置的描述不代表本次交付状态。当前镜像已写入 QSPI 并由用户实际断电、切换中间 QSPI 跳线、重新上电验证。日常保持 QSPI 跳线，上电即可启动，无需打开 Vivado 或加载 ELF。

1. 接好 HDMI、板卡电源和板载 UART；上位机解压整个目录后运行 `Z7_LAB.exe`，选择 **COM27**，点击“连接”。115200 8N1 已由程序设置。JTAG 用于维护，日常使用不必下载。
2. 上电为真实 ADC、10MSa/s、运行；DAC 保持中点码 8192。输入浮空时应看到接近中点的噪声/直线，频率可能 N/A；这不应显示为固定内部 10kHz。SIM 必须显式选择，HDMI 持续提示测试源。
3. 顶部“HDMI: ADC / HDMI: DAC”由 PS 切换显示，双方后台独立运行。顶部“停止 DAC”在所有标签页都能使用。停止保持中点码，未接 PD，不是高阻或物理断电。
4. ADC 标签修改模式、采样率、触发、视窗/垂直位置、FFT、EYE 等后，点击相应应用按钮。“读取板卡参数到控件”同步实际设置；后台状态轮询不覆盖正在编辑的数值。
5. DAC 标签选择正弦/方波/三角/锯齿/直流/表达式/CSV，先预览再上传。默认不勾选“上传成功后开启输出”；上传完成并经 CRC 和 FPGA 表读回确认才切换。勾选后才输出波形。未开启时 HDMI 仍可预览已配置数字表，状态显示保持中点。

ADC 的 ±5V @50Ω 和 DAC 的 5Vpp 是用户提供的模块标称参数。ADC 使用 10V/4095code、零点 2047.5 的初始比例，界面标明“标称”；通过已知输入执行实测校准后才标为校准值。DAC 以 %FS 控制，标称 Vpp 仅作估计。5Vpp 的零中心信号为 ±2.5V；是否整体落入 ADC 的 ±5V 还取决于实际直流偏置及负载，不能只比较 Vpp。停止 DAC 不保证模拟端为 0V。

### 波形与坐标

HDMI 为 1280×720@60Hz，字符采用原生 16×24 中英文点阵。横轴、纵轴随当前采样率、时窗、增益和中心更新。示波为时间/电压，FFT 为有效采样率对应的 Hz/dBFS，EYE 为 0～2UI/电压，DPX 含时间/电压/命中强度，ROLL 为相对当前时间，MEM 为记录起点时间，SEG 为相对触发时间。DAC 为双周期时间/%FS 的配置预览。无参考时钟锁定的 EYE 不报告眼宽或抖动数值。

自动缩放作用于当前 ADC 视窗；连续自动缩放可启停。手动中心移动不改变电压校准零点。FFT 的横轴使用对冻结块平均降采样后的有效采样率，并非始终按原始 ADC 采样率绘制。

### 自定义 DAC

DAC 固定 50MSa/s，与 ADC 的四档采样率无关。2048 点双缓冲和 32 位 DDS 支持 0.1Hz～5MHz 设定，频率量化间隔约 0.01164Hz。实际可设频率、数字表范围和标称 Vpp 在预览旁显示。高频每周期点数减少，数字功能通过不代表模拟带宽或 SFDR 已标定。

表达式变量 `t` 是一个周期的归一化位置 `0≤t<1`，不是秒。结果须在 -1～+1，例如 `sin(2*pi*t)` 或 `where(t<0.25,1,-1)`。频率单独设置。“满幅峰峰值”表示归一化 -1～+1 的跨度，表达式未用满该范围时不自动放大；“零值偏置”对应表达式 y=0。CSV 输入为单列归一化样本，周期插值成 2048 点。导出 CSV 为实际 0～16383 数字码值，不能直接作为归一化输入。保存/加载 JSON 可以复用参数，加载默认关闭输出勾选。

“已确认”表示板卡接受且读回了数字波形表，不是 DAC 模拟端的测量结果。上传失败不会替换当前活动表。ADC 的模式、触发、采样率、来源、暂停、缩放和校准均不改变 DAC 频率、表、相位或启停；全板断电/复位会重启双方。

### Flash 更新与恢复

当前无需再次烧写。后续修改源码后，运行 `build.ps1` 构建并封存 FPGA、ARM、FSBL、BOOT.BIN；新解压工程第一次使用 `build.ps1 -Recreate`。构建需本机 Vivado/SDK 2018.3，脚本的安装路径可按实际环境调整。

厂家流程是在断电后切换 JTAG 启动跳线，再上电并连接 HS2，运行 `flash.ps1`。脚本先检查已封存镜像和原 Flash 备份，再按单片 QSPI x4、偏移 0 擦写并校验；必须出现 `Flash Operation Successful`。完成后断电，切回中间 QSPI 两针，再上电。不要把仅下载 bit 等同于已写入完整启动镜像。

`flash.ps1 -RestoreOriginal` 恢复本次修改前读出的完整 16MiB Flash；该操作也需上述 JTAG 写入条件。原始备份位于 `backup/qspi_before_dac_20261017`，SHA256 与芯片读取 CRC 均在清单中。工程原始完整备份在 `D:\Xilinx\Projects\OSC_ad9226_hdmi_backup_before_DAC_20261017`。脚本默认选择已验证的 HS2 序列号；更换下载器须修改目标选择，避免选中其他板卡。

配置保存目前为易失 RAM 或上位机 JSON；上电恢复固件默认值，不自动恢复此前开启的 DAC。下文为基础 ADC 调试接口。

## 首次启动

接线见Pin_Map.csv。HDMI接板载TMDS接口。本次按用户要求只连接JTAG；UART代码仍支持115200 8N1。正常启动为10MSa/s真实ADC，其他采样档位必须以本次正式实现报告和实板日志为准。先运行构建脚本，再使用program.ps1。只有正式数字时序门禁通过才产生用于下载的bit；任何硬件验收项仍应以真实屏幕、串口与仪器记录为准。

上电默认10MSa/s真实ADC。只有显式执行`adc source sim`才启用内部测试源；画面有持续SIM告警条。内部SIM是可重复DDS三角波，便于区分数字链路问题和ADC/模拟输入问题。未加载PS ELF时，PL也能显示诊断页和16K包络。若DDR初始化超时，JTAG脚本会选择OCM恢复控制台，其命令为s/a/r/p/v，不能误认为完整七模式固件。

## 两键

KEY1短按下移，长按上移。KEY2短按修改当前项；菜单打开时长按返回，菜单关闭时长按反向修改当前项。双键短按开关菜单，双键长按RUN/STOP。组合按下有优先权，不额外生成两个单键短按。

21项菜单覆盖模式、运行、来源、触发类型/边沿/阈值/迟滞、时基、FFT点数与窗、眼图码率、垂直增益、零点、回放偏移、段号、MEM采集、Single重新武装、ADC速率、编码、DDR自检和校准比例。速率切换经停止、配置应答、无DMA活动、切时钟、稳定等待、读回及恢复运行；MEM/SEG资格不满足时给出原因，不允许按键绕过闸门。

## 常用串口命令

```
ver
status
clocks
selftest
mode dso
adc source sim
adc source real
adc encoding offset
adc encoding twos
trig type auto
trig type normal
trig type single
trig level 2048
trig edge rise
trig edge fall
run 0
run 1
mode dpx
mode eye
eye rate 1000000
mode fft
fft n 4096
fft window hann
mode roll
memory test
memory bandwidth
video
segments
adc rate 25
adc rate 50
adc rate 65
memory capture
mode mem
mode seg
errors
errors clear
dma
dpx
menu toggle
menu next
menu edit
config save
config load
```

`cal <uV/code> <zero_code>`必须使用已知输入或实际模块标定得到的比例，不能照抄芯片供电电压作为输入量程。4.0 初始显示模块标称换算，缺少有效记录或 OTR 时电压测量为 N/A。Flat/OTR/不足周期时频率为N/A，并注明原因。FFT幅值为相对12-bit ADC满量程的dBFS，X轴显示实际平均降采样后的Nyquist和bin间隔。

## 模式解释

- DSO：完整16384点，8192点预触发；单次完成后HOLD。STOP保留已有快照。
- DPX：160×90共享密度，6倍显示，PL有界线段栅格化和RMW；8位饱和、每次更新减1。限事件数、实际更新率和丢弃独立显示。
- EYE：已知1–5Mb/s NRZ的2UI折叠。无CDR、无参考锁定，眼宽/抖动始终N/A。10MSa/s对高端码率的每UI采样点有限，应按实际信号评估。
- FFT：1024/2048/4096，Hann/Rect。使用冻结16K块，经boxcar平均缩减到目标点数，避免直接抽点冒充滤波；它不是任意带外信号的完整抗混叠前端。
- ROLL：连续ADC域每100000拍Min/Max，窄脉冲保留；主循环漏读的bin单独计数，不把间隔当连续。暂停显示保持。
- MEM：自检后开放1Mi点有限记录；当前不宣称无死区环形DDR。回放偏移可调，显示原记录来源及首样本序号。
- SEG：最多8个16384点事件及时间戳，回放保留真实来源；触发间死区明确累计。

## 故障定位

先查clocks的锁定和视频帧是否增长。SIM正常而ADC异常：查位序、MODE/DFS、共地、OTR、参考范围与时钟往返时序。FIFO_OVF：查DMA状态、请求长度和实际吞吐，先在低速重测；软件会中止并清FIFO后重试。HIST_DROP：查命中FIFO水位、栅格预算及统计刷新率。N/A是无效结果，不是0。

HDMI全黑但串口可用：读取frame/lock，检查实际720p支持和线缆；不能用仿真PNG证明显示器收到信号。没有UART则先用OCM诊断ELF确认PS UART和MIO配置。所有日志保留原始seq与时间戳；HIL脚本不会打开与板卡无关的蓝牙/虚拟串口。

当前未完成的验收及实测条件必须查Acceptance.json。禁止将代码编译、XSim或host MMIO模型当成板卡性能测量。

## 只接 JTAG 的调试方式

无需连接 UART。`program.ps1` 会同时配置 PL 和启动 ARM ELF；只在 Vivado 点 Program Device 仅加载 bit，不能代替 ARM 启动。随后运行 `./jtag.ps1 ver`、`./jtag.ps1 status`、`./jtag.ps1 selftest`；原有 CLI 均可使用，例如 `./jtag.ps1 mode dso`、`./jtag.ps1 adc source sim`。

调试使用 0x0002F000–0x0002FFFF 的 OCM 保留页，主程序把低 OCM 映射为 Normal Non-cacheable，JTAG 经 DAP AP0 物理读写，不暂停 CPU，不依赖 UART/DDR 缓存一致性。页内保留 ABI、启动阶段、主循环心跳、请求/完成序号、命令与响应。OCM 恢复程序也保留此页和阶段/心跳，但不提供完整七模式命令。

如果 CPU 在旧版 AXI 访问中挂起，新的下载脚本会先执行 system reset 恢复调试，再重新配置和初始化。重复下载不会因为处理器已停止而中断。USB HDMI 抓图可用 `python tests/hil/capture_hdmi.py --output results/2026-10-17/hil/hdmi.png`；该脚本只访问名为 USB3 Video 的采集设备。

2026-10-17 实板修复版：默认仍采集 16K，显示触发点附近 4K（40.96us/div @10MSa/s），可在 TIME SPAN 调整。只接 JTAG 时，`./jtag.ps1 measure` 返回冻结记录的 min/max、code RMS、频率及有效标志。电压量程未标定时保持 N/A。

## 真实输入与频率可信度

用户已确认当前模拟输入浮空。浮空没有已知幅度或可用于验收的稳定频率；不应把内部DDS的10kHz当作ADC真实读数。正常运行默认真实ADC，低幅度/过量程/不足三个交叉点/周期标准差超过平均周期10%的记录均不输出有效频率。界面仍保留实际码值范围与波形；没有电压比例时Vpp、RMS和V/div显示N/A。ADC_CODE的均值及RMS可通过measure读取。

`selftest`会临时选SIM，先检查2MiB DDR模式，再运行SYS域递增码的DDR带宽压力（要求≥143MB/s，即65MSa/s×2Byte的110%），最后逐样本核对1Mi点DDS序列。结束恢复调用前的数据源及RUN状态。自检产生的MEM记录标为SIM，不能作为真实ADC波形使用。`memory bandwidth`会覆盖深记录缓冲并使原MEM记录失效；`memory test`也会使MEM资格和记录失效。

修改采样率会清除MEM/SEG资格及旧记录，须在当前档位重新运行selftest。config save/load只保留易失RAM配置，load同时恢复实际硬件时钟，不写Flash。默认10MSa/s便于开始调试；已实现四档时钟不等于已经标定模块模拟带宽。

`segments`逐段返回长度、64位首样本序号、数据来源、CRC和内部DDS顺序校验；真实ADC段只做CRC一致性，不能把任意输入与DDS金样本比较。`video`返回PL实际RGB帧CRC及软件显示资产CRC；摄像采集卡的色彩转换会改变像素，不能直接要求采集卡PNG的CRC等于PL原始RGB CRC。

ILA操作和位域见Debug_ILA.md。最终板级性能、时间条件和测试日志见Acceptance.json及Delivery_Report.md。

下载前program.ps1会核对已封存bit/HDF/LTX/ELF/PS初始化及构建标记的SHA256，避免新旧输出混用。build.ps1在SDK与最新HDF一致后自动封存；缺少资格标记或任一文件变化时拒绝下载并指出文件名。

正常program.ps1流程在ARM启动验证后自动运行当前10MSa/s的DDR/带宽/DDS自检，恢复真实ADC，再采集一份真实ADC的1Mi点MEM记录。这样首次进入MEM也不会把DDR自测的DDS当作实际输入。快速底层调试可显式使用program.ps1 -SkipSelftest，此时MEM/SEG仍由软件资格闸门控制。SEG首次进入后按实际触发逐段填满，段来源与时间戳可读取。
