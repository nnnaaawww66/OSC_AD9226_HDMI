set root [file normalize [file join [file dirname [info script]] ../..]]
source $root/hw/scripts/jtag_transport.tcl
set out [open $root/results/2026-10-17/prd_completion/functional_hil.log w]
proc check {cmd expected} {
 global out
 set response [scope_jtag_command $cmd]
 puts $out "[clock milliseconds] TX $cmd\n$response";flush $out
 if {![string match *$expected* $response]} {error "Unexpected response: $cmd => $response"}
 return $response
}
proc sample_snapshot {} {
 set t0 [clock milliseconds]
 set v [mrd -value -address-space AP0 0x40000014 2]
 set t1 [clock milliseconds]
 return [list [expr {wide([lindex $v 1])*4294967296+wide([lindex $v 0])}] [expr {($t0+$t1)/2.0}]]
}
if {[catch {
connect -url tcp:127.0.0.1:3121
targets -set -filter {name == "APU"}
check ver product=Z7_SCOPE
check {adc source real} source=ADC
check status source=ADC
foreach rate {10 25 50 65} {
 check "adc rate $rate" "rate=[expr {$rate*1000000}]"
 check selftest selftest=PASS
 check {adc source sim} source=SIM
 after 300
 set m [check measure source=SIM]
 regexp {frequency=([0-9.]+)} $m -> hz
 set target [expr {$rate*1000.0*16777/16777.216}]
 if {abs($hz-$target)>$target*.003} {error "SIM frequency mismatch: $hz expected $target"}
 foreach mode {dso dpx eye fft roll mem seg} {check "mode $mode" "mode=[string toupper $mode]";after 100;check status errors=00000000}
 check {run 0} run=0
 set segments [check segments sequence_ok=1]
 set stamps {}
 foreach {match stamp} [regexp -all -inline {first=([0-9]+)} $segments] {lappend stamps $stamp}
 if {[llength $stamps]!=8} {error "Eight segment timestamps were not returned"}
 set stamps [lsort -integer $stamps]
 for {set j 1} {$j<8} {incr j} {if {[lindex $stamps $j]-[lindex $stamps [expr {$j-1}]]<16384} {error "Segment timestamps overlap"}}
 check {run 1} run=1
 check {mode dso} mode=DSO
 check {adc source real} source=ADC
 after 200
 check measure source=ADC
 check video pixel_crc32=
 check dma drop=0
 check clocks "adc=[expr {$rate*1000000}]"
 set first [sample_snapshot];after 2000;set last [sample_snapshot]
 set measured [expr {([lindex $last 0]-[lindex $first 0])*1000.0/([lindex $last 1]-[lindex $first 1])}]
 puts $out "RATE_COUNTER requested_MSa=$rate measured_Sa_s=$measured";flush $out
 if {abs($measured-$rate*1000000.0)>$rate*1000000.0*.025} {error "ADC clock counter mismatch at $rate: $measured"}
 puts "PRD_RATE_PASS $rate"
}
check {adc rate 10} rate=10000000
check selftest selftest=PASS
check {adc source sim} source=SIM
foreach n {1024 2048 4096} {check "fft n $n" fft_n=;foreach window {hann rect} {check "fft window $window" hann=}}
check {config save} config=save
check {adc rate 25} rate=25000000
check {config load} config=load
check clocks adc=10000000
set names {dso dpx eye fft roll}
for {set i 0} {$i<1000} {incr i} {
 set mode [lindex $names [expr {$i%5}]]
 check "mode $mode" "mode=[string toupper $mode]"
 if {$i%100==0} {check status errors=00000000;puts "PRD_MODE_PROGRESS $i/1000"}
}
check {mode dso} mode=DSO
check {adc source real} source=ADC
check {trig type auto} trigger_updated
check {run 1} run=1
after 300
check measure source=ADC
check status errors=00000000
check video pixel_crc32=
puts $out "PRD_FUNCTIONAL_HIL_PASS rates=4 mode_transitions=1000 final_source=ADC";flush $out
puts PRD_FUNCTIONAL_HIL_PASS
} why]} {puts $out "FAIL $why";flush $out;scope_jtag_restore_real;close $out;puts stderr $why;exit 1}
close $out;disconnect;exit 0
