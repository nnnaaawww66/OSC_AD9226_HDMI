set root [file normalize [file join [file dirname [info script]] ../..]]
source $root/hw/scripts/jtag_transport.tcl
if {[catch {
connect -url tcp:127.0.0.1:3121
targets -set -filter {name == "APU"}
set out [open $root/results/2026-10-17/hil/jtag_acceptance.log w]
proc check {cmd expected} {
 global out
 set response [scope_jtag_command $cmd]
 puts $out "[clock milliseconds] TX $cmd\n$response";flush $out
 if {![string match *$expected* $response]} {error "Unexpected response to $cmd: $response"}
 return $response
}
puts [check ver product=Z7_SCOPE]
puts [check {adc source sim} source=SIM]
puts [check selftest selftest=PASS]
foreach mode {dso dpx eye fft roll mem seg} {
 check "mode $mode" "mode=[string toupper $mode]"
 check status "mode=[string toupper $mode]"
}
set cycles 1000
if {[llength $argv]} {set cycles [lindex $argv 0]}
set names {dso dpx eye fft roll}
set first [mrd -value -address-space AP0 0x40000038]
for {set i 0} {$i<$cycles} {incr i} {
 set mode [lindex $names [expr {$i%5}]]
 check "mode $mode" "mode=[string toupper $mode]"
 if {$i%50==0} {puts "HIL_MODE_PROGRESS $i/$cycles";check status errors=00000000}
}
check {mode dso} mode=DSO
set last [mrd -value -address-space AP0 0x40000038]
if {$last<=$first} {error "Video frame count failed to advance"}
puts [check status errors=00000000]
puts $out "PASS $cycles hardware mode transitions; video $first -> $last";close $out
disconnect
puts "JTAG_HIL_PASS cycles=$cycles"
} failure]} {puts stderr "JTAG_HIL_FAILED: $failure";exit 1}
exit 0
