set root [file normalize [file join [file dirname [info script]] ../..]]
open_project $root/OSC_ad9226_hdmi.xpr
open_bd_design [get_files */scope_core.bd]
if {![llength [get_bd_cells -quiet reset_zero]]} {
 create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 reset_zero
 set_property -dict [list CONFIG.CONST_WIDTH 1 CONFIG.CONST_VAL 0] [get_bd_cells reset_zero]
}
foreach pin {aux_reset_in mb_debug_sys_rst} {
 set p [get_bd_pins reset_0/$pin]
 set n [get_bd_nets -quiet -of_objects $p]
 if {[llength $n]} {disconnect_bd_net $n $p}
 connect_bd_net [get_bd_pins reset_zero/dout] $p
}

validate_bd_design
source $root/hw/scripts/assert_bd_resets.tcl
save_bd_design
generate_target all [get_files */scope_core.bd]
write_bd_tcl -force $root/hw/bd/recreate_scope_bd.tcl
close_project
exit
