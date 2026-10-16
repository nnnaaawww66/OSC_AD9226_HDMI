# 操作与调试说明

## 首次启动

接线见Pin_Map.csv。HDMI接板载TMDS接口。连接板载USB-JTAG以及CH340E Type-C UART，串口115200 8N1。先运行构建脚本，再使用program.ps1。只有正式数字时序门禁通过才产生用于下载的bit；任何硬件验收项仍应以真实屏幕、串口与仪器记录为准。

上电默认10MSa/s SIM，真实输入切换使用菜单或`adc source real`。内部SIM是可重复DDS三角波，便于区分数字链路问题和ADC/模拟输入问题。未加载PS ELF时，PL也能显示诊断页和16K包络。若DDR初始化超时，JTAG脚本会选择OCM恢复控制台，其命令为s/a/r/p/v，不能误认为完整七模式固件。

## 两键

KEY1短按下移，长按上移。KEY2短按修改当前项；菜单打开时长按返回，菜单关闭时长按反向修改当前项。双键短按开关菜单，双键长按RUN/STOP。组合按下有优先权，不额外生成两个单键短按。

21项菜单覆盖模式、运行、来源、触发类型/边沿/阈值/迟滞、时基、FFT点数与窗、眼图码率、垂直增益、零点、回放偏移、段号、MEM采集、Single重新武装、ADC速率、编码、DDR自检和校准比例。高级速率及MEM/SEG资格不满足时给出原因，不允许按键绕过闸门。

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

`cal <uV/code> <zero_code>`必须使用已知输入或实际模块标定得到的比例，不能照抄芯片供电电压作为输入量程。菜单也可手动调整。未配置时Vpp/RMS为N/A。Flat/OTR/不足周期时频率为N/A，并注明原因。FFT幅值为相对12-bit ADC满量程的dBFS，X轴显示实际平均降采样后的Nyquist和bin间隔。

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
