# OCM mailbox ABI v1. Call after connecting and selecting APU.
proc scope_jtag_command {cmd {timeout 60000}} {
 set base 0x2f000
 if {[string length $cmd]>159} {error "Command exceeds 159 bytes"}
 set head [mrd -value -address-space AP0 $base 8]
 if {[lindex $head 0]!=0x53434a54} {error "OCM mailbox absent; run program.ps1"}
 if {[lindex $head 4]!=[lindex $head 5]} {error "Previous command is pending; stage=[lindex $head 2]"}
 binary scan $cmd c* bytes;lappend bytes 0
 mwr -address-space AP0 -size b [expr {$base+32}] $bytes
 set req [expr {([lindex $head 4]+1)&0xffffffff}]
 mwr -address-space AP0 [expr {$base+16}] $req
 set deadline [expr {[clock milliseconds]+$timeout}]
 while {1} {
  set done [mrd -value -address-space AP0 [expr {$base+20}] 3]
  if {[lindex $done 0]==$req} {break}
  if {[clock milliseconds]>$deadline} {error "JTAG command timeout: $cmd"}
  after 20
 }
 set len [lindex $done 2]
 if {$len>2047} {error "Corrupt response length"}
 set response ""
 if {$len>0} {set response [binary format c* [mrd -value -address-space AP0 -size b [expr {$base+192}] $len]]}
 if {[lindex $done 1]} {error "Firmware command failed: $cmd / $response"}
 return $response
}
