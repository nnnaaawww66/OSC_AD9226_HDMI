
set root D:/Xilinx/Projects/OSC_ad9226_hdmi
cd $root
open_project $root/OSC_ad9226_hdmi.xpr
add_files -fileset constrs_1 $root/hw/constraints/cdc.xdc
set_property PROCESSING_ORDER EARLY [get_files board_base.xdc]
set_property PROCESSING_ORDER LATE [get_files adc_interface.xdc]
set_property PROCESSING_ORDER LATE [get_files cdc.xdc]
set_property USED_IN_SYNTHESIS false [get_files cdc.xdc]
reset_run synth_1
close_project
source $root/hw/scripts/build.tcl
