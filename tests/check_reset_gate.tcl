set root [file normalize [file join [file dirname [info script]] ..]]
open_project $root/OSC_ad9226_hdmi.xpr
open_bd_design [get_files */scope_core.bd]
source $root/hw/scripts/assert_bd_resets.tcl
set p [get_bd_pins reset_0/aux_reset_in]
set n [get_bd_nets -of_objects $p]
disconnect_bd_net $n $p
if {![catch {source $root/hw/scripts/assert_bd_resets.tcl} why]} {error "RESET_GATE_TEST: floating input incorrectly accepted"}
puts "PASS RESET_GATE negative test: $why"
connect_bd_net [get_bd_pins reset_zero/dout] $p
source $root/hw/scripts/assert_bd_resets.tcl
close_project
exit
