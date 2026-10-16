set root D:/Xilinx/Projects/OSC_ad9226_hdmi
cd $root
open_project $root/OSC_ad9226_hdmi.xpr
add_files [glob $root/hw/rtl/*.v]
open_bd_design [get_files */scope_bd.bd]
if {[catch {update_module_reference [get_bd_cells scope_0]} msg]} {puts "UPDATE_ERROR=$msg";puts $::errorInfo;error $msg}
validate_bd_design
save_bd_design
write_bd_tcl -force $root/hw/bd/recreate_scope_bd.tcl
set_property synth_checkpoint_mode None [get_files */scope_bd.bd]
generate_target all [get_files */scope_bd.bd]
reset_run synth_1
close_project
source $root/hw/scripts/build.tcl

