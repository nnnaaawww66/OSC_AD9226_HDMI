source $root/hw/scripts/assert_adc_clocks.tcl
source $root/hw/scripts/assert_dac.tcl
set inf [open [get_property DIRECTORY [get_runs impl_1]]/runme.log r]
set impl_log [read $inf];close $inf
if {[string first "CRITICAL WARNING:" $impl_log]>=0} {error "Implementation critical-warning gate failed; inspect runme.log"}
foreach rate {10 25 50 65} {
    foreach delay {max min} {
        report_timing -from [get_ports {adc_data[*] adc_otr}] -group adc_rx$rate -delay_type $delay -max_paths 13 -file $results/adc_${rate}_${delay}.rpt
    }
}
report_utilization -file $results/utilization.rpt
report_timing_summary -delay_type min_max -report_unconstrained -file $results/timing_summary.rpt
report_clock_interaction -file $results/clock_interaction.rpt
report_drc -file $results/drc.rpt
report_io -file $results/io.rpt
report_power -file $results/power.rpt
report_cdc -file $results/cdc.rpt
set cdc_detail [report_cdc -details -return_string]
set f [open $results/cdc_details.rpt w];puts $f $cdc_detail;close $f
source $root/hw/scripts/audit_cdc.tcl
scope_audit_cdc $cdc_detail $results/cdc_review.txt

check_timing -verbose -file $results/check_timing.rpt
set bad_setup [get_timing_paths -quiet -delay_type max -slack_lesser_than 0]
set bad_hold [get_timing_paths -quiet -delay_type min -slack_lesser_than 0]
if {[llength $bad_setup]||[llength $bad_hold]} {error "Timing gate failed; inspect reports. No bitstream released."}
set fatal [get_drc_violations -quiet -filter {SEVERITY == Error}]
if {[llength $fatal]} {error "DRC gate failed: $fatal"}
write_debug_probes -force $results/scope_top.ltx
write_checkpoint -force $results/scope_routed.dcp
write_bitstream -force $results/scope_top.bit
# Keep the GUI's normal Program Device path identical to the qualified release.
file copy -force $results/scope_top.bit [get_property DIRECTORY [get_runs impl_1]]/scope_top.bit
write_hwdef -force -file $results/scope_design.hwdef
write_sysdef -force -hwdef $results/scope_design.hwdef -bitfile $results/scope_top.bit -file $results/scope_top.hdf
set success [open $results/hardware_build.ok w];puts $success "HARDWARE_BUILD_PASS $code_sha [clock format [clock seconds]]";close $success
close_project

