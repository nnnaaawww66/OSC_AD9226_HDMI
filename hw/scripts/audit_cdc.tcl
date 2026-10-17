set scope_cdc_allowlist [file normalize [file join [file dirname [info script]] ../../docs/cdc_review_allowlist.tsv]]
proc scope_audit_cdc {report output} {
 global scope_cdc_allowlist
 set allowed [dict create]
 set f [open $scope_cdc_allowlist r];set content [read $f];close $f
 foreach line [split $content \n] {
  if {$line eq "" || [string index $line 0] eq "#"} {continue}
  set cols [split $line \t]
  if {[llength $cols]!=4} {error "CDC allowlist format"}
  dict set allowed [lrange $cols 0 2] [lindex $cols 3]
 }
 set reviewed 0;set notes {}
 foreach line [split $report \n] {
  if {![regexp {^[ \t]*[0-9]+[ \t]+CDC-[0-9]+[ \t]+Critical[ \t]} $line]} {continue}
  set words [regexp -all -inline {\S+} $line]
  set key [list [lindex $words 1] [lindex $words end-1] [lindex $words end]]
  if {![string match {*False Path*} $line] || ![dict exists $allowed $key]} {error "CDC_GATE_UNREVIEWED: $line"}
  incr reviewed
  append notes "REVIEWED [dict get $allowed $key]\n$line\n"
 }
 set f [open $output w]
 puts $f "CDC_REVIEW_PASS reviewed_critical_rows=$reviewed unreviewed_critical_rows=0"
 puts $f "Raw CDC severities are preserved. Exact tuples only: UG472 clock-control S pins and manufacturer ILA internal configuration paths. Product-to-ILA boundaries are not excluded."
 puts $f $notes;close $f
 puts "CDC_REVIEW_PASS reviewed_critical_rows=$reviewed unreviewed_critical_rows=0"
 return $reviewed
}
