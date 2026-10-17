set root [file normalize [file join [file dirname [info script]] ../..]]
cd $root
set results $root/results/2026-10-17
open_project $root/OSC_ad9226_hdmi.xpr
set_param general.maxThreads 4
open_bd_design [get_files */scope_core.bd]
source $root/hw/scripts/assert_bd_resets.tcl
validate_bd_design
save_bd_design
generate_target all [get_files */scope_core.bd]
set code_sha 00000000
if {![catch {exec git -C $root rev-parse --short=8 HEAD} git_sha]} {set code_sha [string trim $git_sha]}
set_property verilog_define [list "SCOPE_BUILD_SHA=32'h$code_sha"] [get_filesets sources_1]
set f [open $results/build_revision.txt w];puts $f $code_sha;close $f
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed"}
open_run impl_1
report_utilization -file $results/utilization.rpt
report_timing_summary -delay_type min_max -report_unconstrained -file $results/timing_summary.rpt
report_clock_interaction -file $results/clock_interaction.rpt
report_drc -file $results/drc.rpt
report_io -file $results/io.rpt
report_power -file $results/power.rpt
report_cdc -file $results/cdc.rpt
set cdc_detail [report_cdc -details -return_string]
set f [open $results/cdc_details.rpt w];puts $f $cdc_detail;close $f
if {[regexp {CDC-[0-9]+[ \t]+Critical} $cdc_detail]} {error "CDC gate failed; unsafe crossing remains"}

check_timing -verbose -file $results/check_timing.rpt
set bad_setup [get_timing_paths -quiet -delay_type max -slack_lesser_than 0]
set bad_hold [get_timing_paths -quiet -delay_type min -slack_lesser_than 0]
if {[llength $bad_setup]||[llength $bad_hold]} {error "Timing gate failed; inspect reports. No bitstream released."}
set fatal [get_drc_violations -quiet -filter {SEVERITY == Error}]
if {[llength $fatal]} {error "DRC gate failed: $fatal"}
write_checkpoint -force $results/scope_routed.dcp
write_bitstream -force $results/scope_top.bit
# Keep the GUI's normal Program Device path identical to the qualified release.
file copy -force $results/scope_top.bit [get_property DIRECTORY [get_runs impl_1]]/scope_top.bit
write_hwdef -force -file $results/scope_design.hwdef
write_sysdef -force -hwdef $results/scope_design.hwdef -bitfile $results/scope_top.bit -file $results/scope_top.hdf
close_project

