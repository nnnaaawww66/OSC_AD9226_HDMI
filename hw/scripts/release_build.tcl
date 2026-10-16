
set root D:/Xilinx/Projects/OSC_ad9226_hdmi
cd $root
open_project $root/OSC_ad9226_hdmi.xpr
open_bd_design [get_files */scope_core.bd]
update_module_reference [get_bd_cells scope_0]
set_property CONFIG.VIDEO_VGA 0 [get_bd_cells scope_0]
set_property CONFIG.ENABLE_RATE_SWITCH 0 [get_bd_cells scope_0]
set_property generic {VIDEO_VGA=0} [get_filesets sources_1]
validate_bd_design
if {[get_property CONFIG.C_EXT_RESET_HIGH [get_bd_cells reset_0]]!=1} {error "RESET POLARITY"}
save_bd_design
write_bd_tcl -force $root/hw/bd/recreate_scope_bd.tcl
generate_target all [get_files */scope_core.bd]
reset_run synth_1
close_project
source $root/hw/scripts/build.tcl
