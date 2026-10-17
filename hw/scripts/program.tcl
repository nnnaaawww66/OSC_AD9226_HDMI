if {[catch {
# SDK 2018.3 XSCT only. Volatile JTAG programming; never writes Flash.
set root [file normalize [file join [file dirname [info script]] ../..]]
set success $root/results/2026-10-17/program.ok
file delete -force $success
connect -url tcp:127.0.0.1:3121
set devices [targets -target-properties]
puts $devices
# Select only the Zynq-7000 device and Cortex-A9 #0; fail on an ambiguous/missing chain.
# A system reset also recovers a CPU blocked on an unresponsive old AXI slave.
targets -set -filter {name =~ "ARM*#0"}
rst -system
after 500
foreach core {0 1} {
 targets -set -filter [format {name =~ "ARM*#%d"} $core]
 if {[catch {stop} why] && ![string match {*Already stopped*} $why]} {error $why}
}
targets -set -filter {name =~ "xc7z010*"}
fpga -file $root/results/2026-10-17/scope_top.bit
targets -set -filter {name =~ "ARM*#0"}
rst -cores
foreach core {0 1} {
 targets -set -filter [format {name =~ "ARM*#%d"} $core]
 if {[catch {stop} why] && ![string match {*Already stopped*} $why]} {error $why}
}
targets -set -filter {name =~ "ARM*#0"}
source $root/results/2026-10-17/ps7_init.tcl
rename mask_poll vendor_mask_poll
proc mask_poll {addr mask} {
 for {set i 0} {$i < 5000} {incr i} {
  set value [mrd -value $addr]
  if {[expr {$value & $mask}] != 0} {return}
  after 1
 }
 error "PS_INIT_TIMEOUT addr=$addr mask=$mask"
}
if {[catch {ps7_init} init_error]} {
 puts "DDR_INIT_FAILED: $init_error; loading OCM recovery firmware"
 # The vendor PS7 script has already configured MIO/PLL/clocks before DDR.
 # Peripheral init is replayed explicitly so UART is usable after a DDR error.
 set sv [ps_version]
 if {$sv == $PCW_SILICON_VER_1_0} {ps7_peripherals_init_data_1_0} elseif {$sv == $PCW_SILICON_VER_2_0} {ps7_peripherals_init_data_2_0} else {ps7_peripherals_init_data_3_0}
 ps7_post_config
 dow $root/results/2026-10-17/scope_diag.elf
} else {
 ps7_post_config
 dow $root/results/2026-10-17/scope.elf
}
con
disconnect
set f [open $success w];puts $f "JTAG_START_PASS [clock format [clock seconds]]";close $f

} failure]} {puts stderr "PROGRAM_FAILED: $failure";exit 1}
exit 0
