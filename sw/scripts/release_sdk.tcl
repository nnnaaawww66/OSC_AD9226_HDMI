set root [file normalize [file join [file dirname [info script]] ../..]]
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
foreach f [glob $root/sw/diag/*] {file copy -force $f $root/sw/sdk2018/scope_diag/src/}
configapp -app scope build-config release
configapp -app scope compiler-misc {-std=gnu99 -O2 -Wall -Wextra -Werror -Wno-unused-parameter}
configapp -app scope libraries m
configapp -app scope_diag build-config release
projects -build -type all
foreach app {scope scope_diag} {
 set elf $root/sw/sdk2018/$app/Release/$app.elf
 if {![file exists $elf]} {error "ELF missing: $app"}
 file copy -force $elf $root/results/2026-10-17/$app.elf
}
file copy -force $root/sw/sdk2018/scope_hw/ps7_init.tcl $root/results/2026-10-17/ps7_init.tcl
exit
