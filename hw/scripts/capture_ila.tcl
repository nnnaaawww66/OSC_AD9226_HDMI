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
 set cell [get_property CELL_NAME $ila]
 if {[llength $argv] && [lindex $argv 0] eq "videoonly" && ![string match *ila_video $cell]} {continue}
 puts "ILA_INSTANCE $ila cell=$cell"
 report_property $ila
 set_property CONTROL.TRIGGER_POSITION 128 $ila
 if {[string match *ila_sys $cell]} {
  set probes [get_hw_probes -of_objects $ila]
  foreach p $probes {puts "PROBE $p";report_property $p}
  # Bit111 is AXIS TVALID in the documented 128-bit bus.
  set probe [lindex $probes 0]
  set pattern "eq128'b[string repeat X 16]1[string repeat X 111]"
  set_property TRIGGER_COMPARE_VALUE $pattern $probe
  run_hw_ila $ila
  puts "ILA_AXI_ARMED";flush stdout
  set response [exec D:/Xilinx/SDK/2018.3/bin/xsct.bat $root/hw/scripts/jtag_console.tcl memory bandwidth 2>@1]
  if {![string match *JTAG_COMMAND_PASS* $response]} {error "DDR stress command failed: $response"}
  puts $response
 } elseif {[string match *ila_video $cell]} {
  set probe [get_hw_probes -of_objects $ila -filter {NAME =~ */probe0_1}]
  if {[llength $probe]!=1 || [get_property WIDTH $probe]!=3} {error "Video HS/VS/DE probe not found"}
  set_property TRIGGER_COMPARE_VALUE "eq3'bXX1" $probe
  run_hw_ila $ila
 } else {run_hw_ila -trigger_now $ila}
 wait_on_hw_ila -timeout 20 $ila
 set data [upload_hw_ila_data $ila]
 set name [file tail $cell]
 write_hw_ila_data -force -csv_file $out/$name.csv $data
 write_hw_ila_data -force $out/$name.ila $data
 puts "ILA_CAPTURE_PASS $ila"
 if {[string match *ila_sys $cell]} {
  set_property TRIGGER_COMPARE_VALUE "eq128'b[string repeat X 18]1[string repeat X 109]" $probe
  run_hw_ila $ila
  puts [exec D:/Xilinx/SDK/2018.3/bin/xsct.bat $root/hw/scripts/jtag_console.tcl memory bandwidth 2>@1]
  wait_on_hw_ila -timeout 20 $ila
  set data [upload_hw_ila_data $ila]
  write_hw_ila_data -force -csv_file $out/${name}_last.csv $data
 }
 if {[string match *ila_video $cell]} {
  set_property TRIGGER_COMPARE_VALUE "eq3'bX1X" $probe
  run_hw_ila $ila
  wait_on_hw_ila -timeout 20 $ila
  set data [upload_hw_ila_data $ila]
  write_hw_ila_data -force -csv_file $out/${name}_vsync.csv $data
  set_property TRIGGER_COMPARE_VALUE "eq3'b1XX" $probe
  run_hw_ila $ila
  wait_on_hw_ila -timeout 20 $ila
  set data [upload_hw_ila_data $ila]
  write_hw_ila_data -force -csv_file $out/${name}_hsync.csv $data
 }
}
close_hw_target;disconnect_hw_server;close_hw
puts ILA_ALL_DOMAINS_PASS
exit
