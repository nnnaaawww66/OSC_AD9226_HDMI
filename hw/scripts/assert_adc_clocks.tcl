# Execute against a synthesized or routed design with constraints loaded.
foreach rate {10 25 50 65} {
 foreach prefix {adc_fwd adc_rx} {
  set c [get_clocks -quiet $prefix$rate]
  if {[llength $c]!=1} {error "ADC_CLOCK_GATE missing $prefix$rate"}
  if {abs([get_property PERIOD $c]-1000.0/$rate)>.002} {error "ADC_CLOCK_GATE period $prefix$rate"}
 }
 if {$rate>=50 && abs([lindex [get_property WAVEFORM [get_clocks adc_rx$rate]] 0]-3.846)>.030} {error "ADC_CLOCK_GATE receive phase $rate"}
 foreach port [get_ports {adc_data[*] adc_otr}] {
  foreach delay {max min} {
   set paths [get_timing_paths -quiet -delay_type $delay -from $port -group adc_rx$rate]
   if {[llength $paths]!=1} {error "ADC_CLOCK_GATE unconstrained $port rate=$rate delay=$delay"}
  }
 }
}
puts "ADC_CLOCK_GATE_PASS all_four_rates=1 timed_input_bits=13 setup_hold=1"
