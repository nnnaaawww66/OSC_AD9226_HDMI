set root [file normalize [file join [file dirname [info script]] ..]]
open_checkpoint $root/OSC_ad9226_hdmi.runs/synth_1/scope_top.dcp
read_xdc $root/hw/constraints/board_base.xdc
read_xdc $root/hw/constraints/adc_interface.xdc
read_xdc $root/hw/constraints/cdc.xdc
report_clocks -file $root/results/2026-10-17/prd_completion/clock_constraints.rpt
foreach rate {10 25 50 65} {
 foreach prefix {adc_fwd adc_rx} {
  set c [get_clocks -quiet $prefix$rate]
  if {[llength $c]!=1} {error "Missing generated clock $prefix$rate"}
  puts "CLOCK_CHECK $prefix$rate [get_property PERIOD $c] [get_property WAVEFORM $c]"
 }
 set paths [get_timing_paths -from [get_ports {adc_data[*] adc_otr}] -group adc_rx$rate -max_paths 13]
 puts "INPUT_PATH_COUNT $rate [llength $paths]"
 if {[llength $paths]!=13} {error "ADC input paths are not all timed at $rate MHz"}
}
puts "CLOCK_CONSTRAINTS_PASS"
exit
