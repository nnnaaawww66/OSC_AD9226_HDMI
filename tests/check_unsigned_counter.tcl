foreach value {7fffffff 80000000 ffffffff 00000000} {
 scan $value %x signed_low
 set low [expr {$signed_low & 0xffffffff}]
 puts "UNSIGNED_COUNTER low_hex=$value signed_scan=$signed_low normalized=$low"
 if {$low<0 || $low>4294967295} {error "Unsigned low normalization failed"}
}
scan ffffffff %x low
set before [expr {wide(0)*4294967296+($low&0xffffffff)}]
scan 00000000 %x low
set after [expr {wide(1)*4294967296+($low&0xffffffff)}]
if {$after!=$before+1} {error "64-bit counter carry failed"}
set root [file normalize [file join [file dirname [info script]] ..]]
source $root/hw/scripts/jtag_transport.tcl
if {[catch {lsort -integer {241432737596 241433789718}} narrow_failure]} {
 puts "EXPECTED_OLD_TCL_SORT_LIMIT $narrow_failure"
}
set indexes {18446744073709551615 4294967296 241432737596 2147483648 0}
set ordered [lsort -command scope_compare_sample_index $indexes]
if {$ordered ne {0 2147483648 4294967296 241432737596 18446744073709551615}} {error "64-bit sample timestamp sorting failed: $ordered"}
puts "UNSIGNED_64BIT_SORT_PASS $ordered"
puts UNSIGNED_COUNTER_TEST_PASS
exit
