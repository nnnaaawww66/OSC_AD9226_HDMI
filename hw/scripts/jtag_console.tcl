# Non-intrusive OCM command mailbox; CPU need not halt; no UART required.
if {[catch {
connect -url tcp:127.0.0.1:3121
targets -set -filter {name == "APU"}
set base 0x2f000
set cmd [join $argv " "]
if {$cmd eq ""} {set cmd status}
if {[string length $cmd]>159} {error "Command exceeds 159 bytes"}
set head [mrd -value -address-space AP0 $base 8]
if {[lindex $head 0]!=0x53434a54} {error "OCM mailbox absent; run program.ps1 with latest firmware"}
puts [format "JTAG mailbox abi=%u stage=%08x heartbeat=%u" [lindex $head 1] [lindex $head 2] [lindex $head 3]]
if {[lindex $head 4]!=[lindex $head 5]} {error "Previous command is still pending"}
binary scan $cmd c* bytes
lappend bytes 0
mwr -address-space AP0 -size b [expr {$base+32}] $bytes
set req [expr {([lindex $head 4]+1)&0xffffffff}]
mwr -address-space AP0 [expr {$base+16}] $req
set deadline [expr {[clock milliseconds]+60000}]
while {1} {
 set done [mrd -value -address-space AP0 [expr {$base+20}] 3]
 if {[lindex $done 0]==$req} {break}
 if {[clock milliseconds]>$deadline} {error "JTAG command timeout: $cmd"}
 after 100
}
set len [lindex $done 2]
if {$len>2047} {error "Corrupt response length"}
if {$len>0} {puts -nonewline [binary format c* [mrd -value -address-space AP0 -size b [expr {$base+192}] $len]]}
set failed [lindex $done 1]
disconnect
if {$failed} {error "Firmware rejected or failed command: $cmd"}
} failure]} {puts stderr "JTAG_COMMAND_FAILED: $failure";exit 1}
exit 0
