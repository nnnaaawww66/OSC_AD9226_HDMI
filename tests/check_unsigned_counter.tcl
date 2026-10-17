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
puts UNSIGNED_COUNTER_TEST_PASS
exit
