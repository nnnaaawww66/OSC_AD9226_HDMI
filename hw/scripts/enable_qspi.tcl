# Board Rev1.1 U2 W25Q128JV, single x4 on MIO1..6, no feedback clock.
set root [file normalize [file join [file dirname [info script]] ../..]]
open_project $root/OSC_ad9226_hdmi.xpr
open_bd_design [get_files */scope_core.bd]
set_property -dict [list CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {1} CONFIG.PCW_QSPI_QSPI_IO {MIO 1 .. 6} CONFIG.PCW_QSPI_GRP_SINGLE_SS_ENABLE {1} CONFIG.PCW_QSPI_GRP_FBCLK_ENABLE {0} CONFIG.PCW_QSPI_PERIPHERAL_FREQMHZ {200}] [get_bd_cells processing_system7_0]
validate_bd_design
save_bd_design
write_bd_tcl -force $root/hw/bd/recreate_scope_bd.tcl
generate_target all [get_files */scope_core.bd]
close_project
puts QSPI_CONFIG_PASS

