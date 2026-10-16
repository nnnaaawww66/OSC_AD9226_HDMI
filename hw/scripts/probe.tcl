set out [open {D:/Xilinx/Projects/OSC_ad9226_hdmi/results/2026-10-17/tool_probe.txt} w]
puts $out [version]
open_hw
connect_hw_server -url localhost:3121
set ts [get_hw_targets]
puts $out "TARGETS=$ts"
foreach t $ts {current_hw_target $t; open_hw_target; puts $out "DEVICES=[get_hw_devices]"; close_hw_target}
close $out
close_hw
exit
