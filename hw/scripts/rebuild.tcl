
set root D:/Xilinx/Projects/OSC_ad9226_hdmi
cd $root
open_project $root/OSC_ad9226_hdmi.xpr
open_bd_design [get_files */scope_core.bd]
# RTL ports are unchanged; synthesis reads the updated source directly.
validate_bd_design
save_bd_design
generate_target all [get_files */scope_core.bd]
reset_run synth_1
close_project
source $root/hw/scripts/build.tcl

