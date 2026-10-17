if {[catch {
source [file join [file dirname [info script]] jtag_transport.tcl]
connect -url tcp:127.0.0.1:3121
targets -set -filter {name == "APU"}
set cmd [join $argv " "];if {$cmd eq ""} {set cmd status}
puts -nonewline [scope_jtag_command $cmd]
disconnect
} failure]} {puts stderr "JTAG_COMMAND_FAILED: $failure";exit 1}
puts JTAG_COMMAND_PASS
exit 0
