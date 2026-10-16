set root D:/Xilinx/Projects/OSC_ad9226_hdmi
open_project $root/OSC_ad9226_hdmi.xpr
open_bd_design [get_files */scope_bd.bd]
set_property CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {64} [get_bd_cells processing_system7_0]
set_property CONFIG.ASSOCIATED_BUSIF {s_axi:m_axis} [get_bd_pins scope_0/s_axi_aclk]
set_property CONFIG.FREQ_HZ {74250000} [get_bd_ports pixel_clk]
validate_bd_design
save_bd_design
write_bd_tcl -force $root/hw/bd/recreate_scope_bd.tcl
generate_target all [get_files */scope_bd.bd]
write_hwdef -force -file $root/results/2026-10-17/scope_top.hdf
close_project
exit
