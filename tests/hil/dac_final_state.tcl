# Restore the delivered demonstration state with real ADC records, never SIM.
set root [file normalize [file join [file dirname [info script]] ../..]]
source $root/hw/scripts/jtag_transport.tcl
set out [open $root/results/2026-10-17/dac_v4/final_board_state.log w]
proc final_check {cmd expected} {
 global out
 set response [scope_jtag_command $cmd]
 puts $out "[clock milliseconds] TX $cmd\n$response";flush $out
 if {![string match *$expected* $response]} {error "Unexpected final response: $cmd => $response"}
 return $response
}
if {[catch {
connect -url tcp:127.0.0.1:3121
targets -set -filter {name == "APU"}
final_check ver fw=4.0
final_check {dac enable 0} dac_enable=0
final_check {page adc} page=adc
final_check {view auto 0} view_auto=0.000
final_check {view gain 0} view_gain=0.000
final_check {view zero 2047.5} view_zero=2047.500
final_check {view span 4096} view_span=4096.000
final_check status source=ADC
final_check video pixel_crc32=
final_check {mode dso} mode=DSO
final_check {run 1} run=1
final_check {trig type auto} trigger_updated
final_check {adc rate 10} rate=10000000
final_check {adc source real} source=ADC
final_check selftest selftest=PASS
final_check {memory capture} test_kind=0
final_check {mode seg} mode=SEG
after 1500
final_check {run 0} run=0
after 100
set segments [final_check segments source=ADC]
if {[regexp -all {length=16384 first=[0-9]+ source=ADC crc32=[0-9a-f]+ crc_ok=1} $segments]!=8} {error "Eight real ADC segments were not verified"}
set stamps {}
foreach {match stamp} [regexp -all -inline {first=([0-9]+)} $segments] {lappend stamps $stamp}
set stamps [lsort -command scope_compare_sample_index $stamps]
for {set j 1} {$j<8} {incr j} {
 if {[lindex $stamps $j]-[lindex $stamps [expr {$j-1}]]<16384} {error "Final real segment timestamps overlap"}
}
final_check {mode dso} mode=DSO
final_check {run 1} run=1
after 300
set status [final_check status {mode=DSO run=1 source=ADC rate=10000000}]
foreach expected {errors=00000000 mem_gate=1 irq_lost=0} {
 if {![string match *$expected* $status]} {error "Final state failed: $expected / $status"}
}
set dac [final_check {dac status} dac_enabled=0]
if {![string match {*sample_code=8192 hw_enabled=0*} $dac]} {error "DAC not holding midcode: $dac"}
final_check measure source=ADC
final_check clocks adc=10000000
final_check dma drop=0
final_check video pixel_crc32=
puts $out "FINAL_BOARD_STATE_PASS source=ADC rate=10000000 real_segments=8 DAC_midcode=8192 QSPI_programmed_and_power_cycle_verified=1";flush $out
puts FINAL_BOARD_STATE_PASS
} why]} {
 puts $out "FAIL $why";flush $out
 scope_jtag_restore_real
 close $out;puts stderr $why;exit 1
}
close $out;disconnect;exit 0
