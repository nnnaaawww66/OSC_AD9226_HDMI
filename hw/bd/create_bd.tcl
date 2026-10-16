create_bd_design scope_bd
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
source $root/hw/bd/ps7_board_config.tcl
set ps [get_bd_cells processing_system7_0]
set_property -dict [list CONFIG.PCW_USE_M_AXI_GP0 {1} CONFIG.PCW_USE_S_AXI_HP0 {1} CONFIG.PCW_EN_CLK0_PORT {1} CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} CONFIG.PCW_USE_FABRIC_INTERRUPT {1} CONFIG.PCW_IRQ_F2P_INTR {1}] $ps
make_bd_intf_pins_external [get_bd_intf_pins $ps/DDR]
make_bd_intf_pins_external [get_bd_intf_pins $ps/FIXED_IO]
set_property name DDR [get_bd_intf_ports DDR_0]
set_property name FIXED_IO [get_bd_intf_ports FIXED_IO_0]
create_bd_cell -type module -reference scope_peripheral scope_0
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 reset_0
set_property CONFIG.C_EXT_RESET_HIGH {1} [get_bd_cells reset_0]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ctrl_bus
set_property CONFIG.NUM_MI {2} [get_bd_cells ctrl_bus]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 hp_bus
set_property CONFIG.NUM_MI {1} [get_bd_cells hp_bus]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0
set_property -dict [list CONFIG.c_include_sg {0} CONFIG.c_include_mm2s {0} CONFIG.c_include_s2mm {1} CONFIG.c_s_axis_s2mm_tdata_width {16} CONFIG.c_m_axi_s2mm_data_width {64} CONFIG.c_sg_length_width {23} CONFIG.c_s2mm_burst_size {16}] [get_bd_cells axi_dma_0]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 irq_concat
set_property CONFIG.NUM_PORTS {2} [get_bd_cells irq_concat]
connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_GP0] [get_bd_intf_pins ctrl_bus/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_bus/M00_AXI] [get_bd_intf_pins scope_0/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_bus/M01_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins scope_0/M_AXIS] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] [get_bd_intf_pins hp_bus/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins hp_bus/M00_AXI] [get_bd_intf_pins $ps/S_AXI_HP0]
create_bd_port -dir I -type clk sys_clk
set_property CONFIG.FREQ_HZ {100000000} [get_bd_ports sys_clk]
foreach pin {processing_system7_0/M_AXI_GP0_ACLK processing_system7_0/S_AXI_HP0_ACLK reset_0/slowest_sync_clk ctrl_bus/ACLK ctrl_bus/S00_ACLK ctrl_bus/M00_ACLK ctrl_bus/M01_ACLK hp_bus/ACLK hp_bus/S00_ACLK hp_bus/M00_ACLK axi_dma_0/s_axi_lite_aclk axi_dma_0/m_axi_s2mm_aclk scope_0/s_axi_aclk} {
 connect_bd_net [get_bd_ports sys_clk] [get_bd_pins $pin]
}
foreach name {sys_locked sys_reset} pin {dcm_locked ext_reset_in} {
 create_bd_port -dir I $name
 connect_bd_net [get_bd_ports $name] [get_bd_pins reset_0/$pin]
}
foreach pin {ctrl_bus/ARESETN ctrl_bus/S00_ARESETN ctrl_bus/M00_ARESETN ctrl_bus/M01_ARESETN hp_bus/ARESETN hp_bus/S00_ARESETN hp_bus/M00_ARESETN axi_dma_0/axi_resetn scope_0/s_axi_aresetn} {
 connect_bd_net [get_bd_pins reset_0/peripheral_aresetn] [get_bd_pins $pin]
}
connect_bd_net [get_bd_pins scope_0/irq] [get_bd_pins irq_concat/In0]
connect_bd_net [get_bd_pins axi_dma_0/s2mm_introut] [get_bd_pins irq_concat/In1]
connect_bd_net [get_bd_pins irq_concat/dout] [get_bd_pins $ps/IRQ_F2P]
foreach pin {adc_clk_in pixel_clk video_locked adc_locked adc_data adc_otr key_n rate_sel rgb hs vs de} {
 make_bd_pins_external [get_bd_pins scope_0/$pin]
 set_property name $pin [get_bd_ports ${pin}_0]
}
assign_bd_address
set_property offset 0x40000000 [get_bd_addr_segs processing_system7_0/Data/SEG_scope_0_reg0]
set_property range 1M [get_bd_addr_segs processing_system7_0/Data/SEG_scope_0_reg0]
set_property offset 0x40400000 [get_bd_addr_segs processing_system7_0/Data/SEG_axi_dma_0_Reg]
validate_bd_design
save_bd_design
write_bd_tcl -force $root/hw/bd/recreate_scope_bd.tcl
set f [open $root/results/2026-10-17/ip_inventory.txt w]
foreach cell [get_bd_cells -hier -filter {TYPE == ip}] {puts $f "$cell [get_property VLNV $cell]"}
close $f
