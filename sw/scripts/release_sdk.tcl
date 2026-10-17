if {[catch {
set root [file normalize [file join [file dirname [info script]] ../..]]
set success $root/results/2026-10-17/sdk_build.ok
file delete -force $success
setws $root/sw/sdk2018
if {[file exists $root/sw/sdk2018/scope_hw/.project]} {
 updatehw -hw scope_hw -newhwspec $root/results/2026-10-17/scope_top.hdf
} else {
 createhw -name scope_hw -hwspec $root/results/2026-10-17/scope_top.hdf
 createbsp -name scope_bsp -hwproject scope_hw -proc ps7_cortexa9_0 -os standalone
 createapp -name scope -hwproject scope_hw -proc ps7_cortexa9_0 -os standalone -bsp scope_bsp -lang C -app {Empty Application}
 createapp -name scope_diag -hwproject scope_hw -proc ps7_cortexa9_0 -os standalone -bsp scope_bsp -lang C -app {Empty Application}
}
foreach f [glob $root/sw/src/* $root/sw/include/*] {file copy -force $f $root/sw/sdk2018/scope/src/}
file copy -force $root/sw/include/scope_debug.h $root/sw/sdk2018/scope_diag/src/
foreach f [glob $root/sw/diag/*] {file copy -force $f $root/sw/sdk2018/scope_diag/src/}
configapp -app scope build-config release
configapp -app scope -set compiler-misc {-c -fmessage-length=0 -mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard -std=gnu99 -O2 -Wall -Wextra -Werror -Wno-unused-parameter}
if {[catch {configapp -app scope libraries m} msg]} {if {![string match {*already contains the item m*} $msg]} {error $msg}}
configapp -app scope_diag build-config release
projects -build -type all
foreach app {scope scope_diag} {
 set elf $root/sw/sdk2018/$app/Release/$app.elf
 if {![file exists $elf]} {error "ELF missing: $app"}
 file copy -force $elf $root/results/2026-10-17/$app.elf
}
file copy -force $root/sw/sdk2018/scope_hw/ps7_init.tcl $root/results/2026-10-17/ps7_init.tcl

set f [open $success w];puts $f "SDK_BUILD_PASS [clock format [clock seconds]]";close $f

} failure]} {puts stderr "SDK_BUILD_FAILED: $failure";exit 1}
exit 0
