set root [file normalize [file join [file dirname [info script]] ..]]
open_checkpoint $root/OSC_ad9226_hdmi.runs/impl_1/scope_top_routed.dcp
# A positive early receive phase captures the conversion launched on the prior forwarded edge.
# Setup moves to the following edge; hold deliberately moves with it (no compensating hold exception).
set_multicycle_path 2 -setup -from [get_ports {adc_data[*] adc_otr}] -to [get_clocks adc_rx50]
set_multicycle_path 2 -setup -from [get_ports {adc_data[*] adc_otr}] -to [get_clocks adc_rx65]
foreach rate {10 25 50 65} {
 set setup [get_timing_paths -from [get_ports {adc_data[*] adc_otr}] -group adc_rx$rate -delay_type max]
 set hold [get_timing_paths -from [get_ports {adc_data[*] adc_otr}] -group adc_rx$rate -delay_type min]
 puts "EDGE_REQUIREMENT rate=$rate setup=[get_property REQUIREMENT $setup] hold=[get_property REQUIREMENT $hold]"
 puts "ADC_LATENCY_RESULT rate=$rate setup=[get_property SLACK $setup] hold=[get_property SLACK $hold]"
 report_timing -from [get_ports {adc_data[*] adc_otr}] -group adc_rx$rate -delay_type min_max -max_paths 1 -file $root/results/2026-10-17/prd_completion/latency_adc$rate.rpt
}
report_timing_summary -delay_type min_max -file $root/results/2026-10-17/prd_completion/latency_exploration.rpt
exit
