# Fail before synthesis if an inactive reset is tied to its active level.
foreach pin {aux_reset_in mb_debug_sys_rst} {
 set n [get_bd_nets -quiet -of_objects [get_bd_pins reset_0/$pin]]
 if {[llength $n]!=1} {error "RESET_GATE: reset_0/$pin has no explicit net"}
 set drivers [get_bd_pins -quiet -of_objects $n -filter {DIR == O}]
 if {[llength $drivers]!=1 || [string trimleft [lindex $drivers 0] /] ne "reset_zero/dout"} {
  error "RESET_GATE: reset_0/$pin must be driven by reset_zero/dout; drivers=$drivers"
 }
}
if {[get_property CONFIG.CONST_VAL [get_bd_cells reset_zero]]!=0} {error "RESET_GATE: inactive reset must be zero"}
if {[get_property CONFIG.C_EXT_RESET_HIGH [get_bd_cells reset_0]]!=1 || [get_property CONFIG.C_AUX_RESET_HIGH [get_bd_cells reset_0]]!=1} {error "RESET_GATE: reset polarity changed"}
puts "PASS RESET_GATE: auxiliary/debug reset explicitly inactive, external reset active high"
