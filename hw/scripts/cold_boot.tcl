# Read-only proof. Never initializes PS, downloads firmware or programs PL.
if {[catch {
set root [file normalize [file join [file dirname [info script]] ../..]]
source $root/hw/scripts/jtag_transport.tcl
connect -url tcp:127.0.0.1:3121
after 1500
targets -set -filter {name == "APU"}
set boot [expr {[mrd -value -address-space AP0 0xf800025c]+0}]
if {($boot&15)!=1} {error "BOOT_MODE_NOT_QSPI value=$boot"}
set head [mrd -value -address-space AP0 0x2f000 8]
if {[lindex $head 0]!=0x53434a54 || [lindex $head 2]!=6} {error "FLASH_APPLICATION_NOT_RUNNING $head"}
set h1 [lindex $head 3]
after 200
set h2 [expr {[mrd -value -address-space AP0 0x2f00c]+0}]
if {$h1==$h2} {error "FLASH_APPLICATION_HEARTBEAT_STALLED"}
set ver [scope_jtag_command ver]
if {![string match {*rtl=00040000*} $ver]} {error "Unexpected Flash version: $ver"}
set state [scope_jtag_command status]
set dac [scope_jtag_command {dac status}]
if {![string match {*source=ADC rate=10000000*} $state] || ![string match {*dac_enabled=0*} $dac]} {error "Unexpected boot defaults: $state $dac"}
file mkdir $root/results/2026-10-17/dac_v4
set f [open $root/results/2026-10-17/dac_v4/cold_boot.txt w]
puts $f "QSPI_COLD_BOOT_PASS boot_mode=$boot heartbeat_before=$h1 heartbeat_after=$h2"
puts $f $ver;puts $f $state;puts $f $dac
close $f
disconnect
puts QSPI_COLD_BOOT_PASS
} why]} {puts stderr "COLD_BOOT_FAILED: $why";exit 1}
exit 0
