
set root D:/Xilinx/Projects/OSC_ad9226_hdmi
cd $root
open_project $root/OSC_ad9226_hdmi.xpr
add_files $root/hw/rtl/scope_raster.v
open_bd_design [get_files */scope_core.bd]
delete_bd_objs [get_bd_ports sys_reset]
create_bd_port -dir I -type rst sys_reset
connect_bd_net [get_bd_ports sys_reset] [get_bd_pins reset_0/ext_reset_in]
set_property CONFIG.POLARITY ACTIVE_HIGH [get_bd_ports sys_reset]
set_property CONFIG.ASSOCIATED_RESET sys_reset [get_bd_ports sys_clk]
validate_bd_design
if {[get_property CONFIG.C_EXT_RESET_HIGH [get_bd_cells reset_0]] != 1} {error "RESET POLARITY DID NOT PROPAGATE"}
save_bd_design
write_bd_tcl -force $root/hw/bd/recreate_scope_bd.tcl
generate_target all [get_files */scope_core.bd]
write_hwdef -force -file $root/results/2026-10-17/scope_top.hdf
reset_run synth_1
close_project
source $root/hw/scripts/build.tcl


