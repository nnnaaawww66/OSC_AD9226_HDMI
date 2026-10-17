set root [file normalize [file join [file dirname [info script]] ../..]]
set results $root/results/2026-10-17
set f [open $results/build_revision.txt r];set code_sha [string trim [read $f]];close $f
open_project $root/OSC_ad9226_hdmi.xpr
open_run impl_1
source $root/hw/scripts/qualify_export.tcl
exit
