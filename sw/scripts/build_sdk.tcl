set root [file normalize [file join [file dirname [info script]] ../..]]
setws $root/sw/sdk2018
createhw -name scope_hw -hwspec $root/results/2026-10-17/scope_top.hdf
createbsp -name scope_bsp -hwproject scope_hw -proc ps7_cortexa9_0 -os standalone
createapp -name scope -hwproject scope_hw -proc ps7_cortexa9_0 -os standalone -bsp scope_bsp -lang C -app {Empty Application}
importsources -name scope -path $root/sw/src
importsources -name scope -path $root/sw/include
configapp -app scope build-config release
configapp -app scope compiler-misc {-std=gnu99 -O2 -Wall -Wextra -Wno-unused-parameter}
configapp -app scope libraries m
projects -build -type all
exit
