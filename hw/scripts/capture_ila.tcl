set root [file normalize [file join [file dirname [info script]] ../..]]
set out $root/results/2026-10-17/prd_completion/ila
file mkdir $out
open_hw
connect_hw_server -url localhost:3121
set targets [get_hw_targets *201706300081*]
if {[llength $targets]!=1} {error "JTAG HS2 identity ambiguous/missing: $targets"}
open_hw_target [lindex $targets 0]
set dev [get_hw_devices xc7z010*]
if {[llength $dev]!=1} {error "Expected one XC7Z010: $dev"}
current_hw_device $dev
set_property PROBES.FILE $root/results/2026-10-17/scope_top.ltx $dev
refresh_hw_device $dev
set ilas [get_hw_ilas -of_objects $dev]
if {[llength $ilas]!=3} {error "Expected 3 ILA domains, got $ilas"}
foreach ila $ilas {
 puts "ILA_INSTANCE $ila"
 report_property $ila
 set_property CONTROL.TRIGGER_POSITION 128 $ila
 if {[string match *ila_sys* $ila]} {
  set probes [get_hw_probes -of_objects $ila]
  foreach p $probes {puts "PROBE $p";report_property $p}
  # Bit111 is AXIS TVALID in the documented 128-bit bus.
  set probe [lindex $probes 0]
  set pattern "eq128'b[string repeat X 16]1[string repeat X 111]"
  set_property TRIGGER_COMPARE_VALUE $pattern $probe
  run_hw_ila $ila
  puts "ILA_AXI_ARMED";flush stdout
  set response [exec D:/Xilinx/SDK/2018.3/bin/xsct.bat $root/hw/scripts/jtag_console.tcl memory bandwidth]
  puts $response
 } else {run_hw_ila -trigger_now $ila}
 wait_on_hw_ila -timeout 20 $ila
 set data [upload_hw_ila_data $ila]
 set name [regsub -all {[^a-zA-Z0-9_-]} $ila _]
 write_hw_ila_data -force -csv_file $out/$name.csv $data
 write_hw_ila_data -force $out/$name.ila $data
 puts "ILA_CAPTURE_PASS $ila"
}
close_hw_target;disconnect_hw_server;close_hw
puts ILA_ALL_DOMAINS_PASS
exit
