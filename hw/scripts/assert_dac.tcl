set dac_ports [get_ports {dac_data[*]}]
if {[llength $dac_ports]!=14} {error "DAC_GATE: expected 14 data pins"}
set dac_clock [get_clocks dac_fwd]
if {[llength $dac_clock]!=1 || abs([get_property PERIOD $dac_clock]-20)>0.001} {error "DAC_GATE: expected independent 50MHz forwarded clock"}
set memories [get_cells -hier -filter {NAME =~ */dac/table_mem_reg* && REF_NAME =~ RAMB*}]
if {[llength $memories]<2 || [llength $memories]>4} {error "DAC_GATE: table must map to dual-port Block RAM, got $memories"}
foreach p $dac_ports {
 foreach delay {max min} {
  set paths [get_timing_paths -quiet -to $p -delay_type $delay -max_paths 1]
  if {[llength $paths]!=1} {error "DAC_GATE: missing $delay path for $p"}
  if {[get_property SLACK [lindex $paths 0]]<0} {error "DAC_GATE: $delay violation on $p"}
 }
}
report_timing -to $dac_ports -delay_type max -max_paths 14 -file $results/dac_setup.rpt
report_timing -to $dac_ports -delay_type min -max_paths 14 -file $results/dac_hold.rpt
set f [open $results/dac_gate.txt w]
puts $f "DAC_GATE_PASS 14 output pins,50MSa/s,setup_and_hold_checked,dual_port_BRAM=[llength $memories]"
close $f
puts DAC_GATE_PASS
