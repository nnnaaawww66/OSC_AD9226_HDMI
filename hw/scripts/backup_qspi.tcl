if {[catch {
set root [file normalize [file join [file dirname [info script]] ../..]]
set out $root/backup/qspi_before_dac_20261017
file mkdir $out
if {[file exists $out/qspi_16MiB.bin]} {error "Preserve existing Flash backup; refusing overwrite"}
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#0"}
catch {stop}
source $root/results/2026-10-17/ps7_init.tcl
ps7_init
ps7_post_config
dow $root/boot/flash_read.elf
con
targets -set -filter {name == "APU"}
set deadline [expr {[clock milliseconds]+60000}]
while {1} {
 set r [mrd -value -address-space AP0 0x2f000 5]
 if {[lindex $r 0]==0x51535049 && [lindex $r 1]==2} {break}
 if {[lindex $r 1]>=0xe000 && [lindex $r 0]==0x51535049} {error "QSPI helper rejected hardware: $r"}
 if {[clock milliseconds]>$deadline} {error "QSPI read timeout $r"}
 after 250
}
set f [open $out/chip_and_crc.txt w];puts $f $r;close $f
mrd -address-space AP0 -bin -file $out/qspi_16MiB.bin 0x11000000 4194304
if {[file size $out/qspi_16MiB.bin]!=16777216} {error "Incomplete QSPI backup"}
disconnect
puts QSPI_BACKUP_PASS
} failure]} {puts stderr "QSPI_BACKUP_FAILED: $failure";exit 1}
exit 0
