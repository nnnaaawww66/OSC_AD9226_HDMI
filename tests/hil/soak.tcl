set root [file normalize [file join [file dirname [info script]] ../..]]
source $root/hw/scripts/jtag_transport.tcl
set duration 3605
if {[llength $argv]} {set duration [lindex $argv 0]}
set log [open $root/results/2026-10-17/prd_completion/soak.log w]
if {[catch {
connect -url tcp:127.0.0.1:3121
targets -set -filter {name == "APU"}
set start [clock milliseconds]
set last_frame -1;set last_samples -1;set last_heartbeat -1;set checks 0
puts $log "START [clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S%z}] duration_s=$duration"
puts $log [scope_jtag_command {mode dso}]
puts $log [scope_jtag_command {run 1}]
puts $log [scope_jtag_command {adc rate 65}]
puts $log [scope_jtag_command selftest]
puts $log [scope_jtag_command {adc source real}]
puts $log [scope_jtag_command {trig type auto}]
puts $log [scope_jtag_command {memory capture}]
puts $log [scope_jtag_command clocks]
while {[clock milliseconds]-$start < $duration*1000} {
 set s [scope_jtag_command status]
 set h [expr {[mrd -value -address-space AP0 0x2f00c]+0}]
 if {![regexp {source=ADC rate=65000000.*frame=([0-9]+) samples=([0-9]+):([0-9a-f]+).*otr=([0-9]+) drop=([0-9]+) errors=([0-9a-f]+)} $s -> frame hi lo otr drop errors]} {error "Status parse/source/rate failed: $s"}
 scan $lo %x low;set sample [expr {wide($hi)*4294967296+($low & 0xffffffff)}]
 if {$frame<=$last_frame || $sample<=$last_samples || $h==$last_heartbeat || $drop!=0 || $errors ne "00000000"} {error "Continuity/error assertion: $s heartbeat=$h"}
 set locks [expr {[mrd -value -address-space AP0 0x40000024]+0}]
 if {($locks&0xc00)!=0xc00} {error "MMCM lock lost $locks"}
 set last_frame $frame;set last_samples $sample;set last_heartbeat $h;incr checks
 puts $log "[clock milliseconds] heartbeat=$h locks=$locks $s";flush $log
 if {$checks%60==0} {puts "SOAK_PROGRESS elapsed_s=[expr {([clock milliseconds]-$start)/1000}] checks=$checks";puts $log [scope_jtag_command measure];puts $log [scope_jtag_command video]}
 after 1000
}
puts $log "PASS duration_ms=[expr {[clock milliseconds]-$start}] checks=$checks frame=$last_frame samples=$last_samples";flush $log
puts SOAK_PASS
} why]} {puts $log "FAIL $why";close $log;puts stderr $why;exit 1}
close $log;disconnect;exit 0
