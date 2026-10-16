
set root [file normalize [file join [file dirname [info script]] ../..]]
cd $root
if {[version -short] ne "2018.3"} {error "Vivado 2018.3 required"}
create_project OSC_ad9226_hdmi $root -part xc7z010clg400-1 -force
set_property target_language Verilog [current_project]
set_property XPM_LIBRARIES {XPM_CDC XPM_MEMORY XPM_FIFO} [current_project]
add_files [glob $root/hw/rtl/*.v]
add_files [glob $root/hw/vendor/*.v]
add_files [glob $root/hw/rtl/*.mem]
add_files -fileset constrs_1 [glob $root/hw/constraints/*.xdc]
set_property PROCESSING_ORDER EARLY [get_files board_base.xdc]
set_property PROCESSING_ORDER LATE [get_files adc_interface.xdc]
set_property PROCESSING_ORDER LATE [get_files cdc.xdc]
set_property USED_IN_SYNTHESIS false [get_files cdc.xdc]
set_property top scope_top [get_filesets sources_1]
update_compile_order -fileset sources_1
source $root/hw/bd/recreate_scope_bd.tcl
set_property CONFIG.VIDEO_VGA 0 [get_bd_cells scope_0]
set_property CONFIG.ENABLE_RATE_SWITCH 0 [get_bd_cells scope_0]
set_property generic {VIDEO_VGA=0} [get_filesets sources_1]
set_property CONFIG.FREQ_HZ 74250000 [get_bd_ports pixel_clk]
validate_bd_design
if {[get_property CONFIG.C_EXT_RESET_HIGH [get_bd_cells reset_0]] != 1} {error "RESET POLARITY"}
set_property synth_checkpoint_mode None [get_files */scope_core.bd]
save_bd_design
generate_target all [get_files */scope_core.bd]
write_bd_tcl -force $root/hw/bd/recreate_scope_bd.tcl
update_compile_order -fileset sources_1
close_project
