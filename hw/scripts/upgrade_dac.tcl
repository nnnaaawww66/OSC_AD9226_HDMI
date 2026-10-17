set root [file normalize [file join [file dirname [info script]] ../..]]
open_project $root/OSC_ad9226_hdmi.xpr
add_files -norecurse $root/hw/rtl/scope_dac.v
add_files -fileset constrs_1 $root/hw/constraints/dac_interface.xdc
set_property PROCESSING_ORDER LATE [get_files dac_interface.xdc]
open_bd_design [get_files */scope_core.bd]
update_module_reference scope_core_scope_0_0
create_bd_port -dir I -type clk dac_clock
set_property CONFIG.FREQ_HZ 50000000 [get_bd_ports dac_clock]
create_bd_port -dir O -from 13 -to 0 dac_data
connect_bd_net [get_bd_ports dac_clock] [get_bd_pins scope_0/dac_clock]
connect_bd_net [get_bd_ports dac_data] [get_bd_pins scope_0/dac_data]
validate_bd_design
save_bd_design
generate_target all [get_files */scope_core.bd]
update_compile_order -fileset sources_1
close_project
puts DAC_UPGRADE_PASS

