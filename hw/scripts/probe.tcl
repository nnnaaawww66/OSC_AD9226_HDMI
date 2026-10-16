
set root [file normalize [file join [file dirname [info script]] ../..]]
set out [open $root/results/2026-10-17/tool_probe.txt w]
puts $out [version]
open_hw
connect_hw_server -url localhost:3121
if {[catch {get_hw_targets} found]} {set found {}}
puts $out "TARGETS=$found"
foreach t $found {current_hw_target $t;open_hw_target;puts $out "DEVICES=[get_hw_devices]";close_hw_target}
close $out
close_hw
exit
