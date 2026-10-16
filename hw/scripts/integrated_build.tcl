set root D:/Xilinx/Projects/OSC_ad9226_hdmi
cd $root
open_project $root/OSC_ad9226_hdmi.xpr
remove_files [get_files */scope_bd.bd]
set f [open $root/hw/rtl/scope_top.v r];set txt [read $f];close $f
set f [open $root/hw/rtl/scope_top.v w];puts $f [string map {"scope_bd system" "scope_core system"} $txt];close $f
set f [open $root/hw/bd/create_bd.tcl r];set txt [read $f];close $f
set txt [string map {"create_bd_design scope_bd" "create_bd_design scope_core" "CONFIG.C_EXT_RESET_HIGH {1}" "CONFIG.C_AUX_RESET_HIGH {1}"} $txt]
set txt [string map {"CONFIG.c_s_axis_s2mm_tdata_width {16}" "" "CONFIG.c_m_axi_s2mm_data_width {64}" "CONFIG.c_m_axi_s2mm_data_width {32}"} $txt]
eval $txt
set_property synth_checkpoint_mode None [get_files */scope_core.bd]
generate_target all [get_files */scope_core.bd]
reset_run synth_1
close_project
source $root/hw/scripts/build.tcl
