set root [file normalize [file join [file dirname [info script]] ../..]]
cd $root
set results $root/results/2026-10-17
file delete -force $results/hardware_build.ok
open_project $root/OSC_ad9226_hdmi.xpr
foreach init_file [glob $root/hw/rtl/*.mem] {
 if {[llength [get_files -quiet $init_file]]==0} {add_files -norecurse $init_file}
}
set_param general.maxThreads 4
source $root/hw/scripts/setup_ila.tcl
open_bd_design [get_files */scope_core.bd]
set_property CONFIG.ENABLE_RATE_SWITCH 1 [get_bd_cells scope_0]
source $root/hw/scripts/assert_bd_resets.tcl
validate_bd_design
save_bd_design
write_bd_tcl -force $root/hw/bd/recreate_scope_bd.tcl
generate_target all [get_files */scope_core.bd]
set code_sha 00000000
if {![catch {exec git -C $root rev-parse --short=8 HEAD} git_sha]} {set code_sha [string trim $git_sha]}
set_property verilog_define [list "SCOPE_BUILD_SHA=32'h$code_sha" SCOPE_ILA] [get_filesets sources_1]
set f [open $results/build_revision.txt w];puts $f $code_sha;close $f
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
set sf [open [get_property DIRECTORY [get_runs synth_1]]/runme.log r]
set synth_log [read $sf];close $sf
if {[string first "CRITICAL WARNING:" $synth_log]>=0} {error "Synthesis critical-warning gate failed; inspect runme.log"}
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed"}
open_run impl_1
source $root/hw/scripts/qualify_export.tcl
