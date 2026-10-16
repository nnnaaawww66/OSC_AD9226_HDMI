set root [file normalize [file join [file dirname [info script]] ../..]]
set build_script $root/hw/scripts/build.tcl
if {[catch {source $build_script} failure]} {
 if {![string match {*Timing gate failed*} $failure] && ![string match {*Implementation failed*} $failure]} {error $failure}
 set f [open $root/results/2026-10-17/video_downgrade.txt w];puts $f "720p build rejected: $failure; retry 640x480@60 with full constraints";close $f
 catch {close_design};catch {close_project}
 open_project $root/OSC_ad9226_hdmi.xpr
 open_bd_design [get_files */scope_core.bd]
 set_property CONFIG.VIDEO_VGA 1 [get_bd_cells scope_0]
 set_property generic {VIDEO_VGA=1} [get_filesets sources_1]
 validate_bd_design
 save_bd_design
 write_bd_tcl -force $root/hw/bd/recreate_scope_bd.tcl
 generate_target all [get_files */scope_core.bd]
 reset_run synth_1
 close_project
 source $build_script
}
exit
