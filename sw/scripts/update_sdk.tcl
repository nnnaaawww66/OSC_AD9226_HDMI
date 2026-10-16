
set root D:/Xilinx/Projects/OSC_ad9226_hdmi
setws $root/sw/sdk2018
foreach f [glob $root/sw/src/* $root/sw/include/*] {file copy -force $f $root/sw/sdk2018/scope/src/}
projects -build -type app -name scope
set f [open $root/results/2026-10-17/firmware_build.txt w]
puts $f "ELF=[file size $root/sw/sdk2018/scope/Release/scope.elf]"
close $f
exit
