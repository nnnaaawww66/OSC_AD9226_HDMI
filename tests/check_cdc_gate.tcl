set root [file normalize [file join [file dirname [info script]] ..]]
source $root/hw/scripts/audit_cdc.tcl
set f [open $root/results/2026-10-17/cdc_details.rpt r];set raw [read $f];close $f
scope_audit_cdc $raw $root/results/2026-10-17/prd_completion/cdc_gate_positive.txt
foreach fake {
 {1  CDC-1  Critical  unknown  0  False Path  system/product_source/C  system/product_dest/D}
 {2  CDC-1  Critical  unknown  0  False Path  system/scope_0/inst/ila_adc/inst/unknown/C  system/product_dest/D}
} {
 if {![catch {scope_audit_cdc "$raw\n$fake" $root/results/2026-10-17/prd_completion/cdc_gate_should_not_exist.txt} why]} {error "CDC negative test accepted unknown path"}
 puts "PASS CDC_GATE_NEGATIVE $why"
}
puts CDC_GATE_TEST_PASS
exit
