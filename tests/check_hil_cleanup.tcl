set root [file normalize [file join [file dirname [info script]] ..]]
source $root/hw/scripts/jtag_transport.tcl
rename scope_jtag_command scope_jtag_command_real
set calls {}
set reject ""
proc scope_jtag_command {cmd timeout} {
 global calls reject
 lappend calls $cmd
 if {$cmd eq $reject} {error "injected transport failure"}
 return OK
}
if {![scope_jtag_restore_real]} {error "Normal cleanup rejected"}
set expected {{adc source real} {mode dso} {trig type auto} {run 1}}
if {$calls ne $expected} {error "Wrong cleanup commands $calls"}
set calls {};set reject {adc source real}
if {[scope_jtag_restore_real]} {error "Failed REAL restoration was accepted"}
if {$calls ne $expected} {error "Cleanup stopped after one failed command"}
puts HIL_CLEANUP_TEST_PASS
exit
