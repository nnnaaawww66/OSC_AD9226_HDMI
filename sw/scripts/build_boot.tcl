# Generate FSBL against the actual new hardware. FLASH writing is separate.
if {[catch {
set root [file normalize [file join [file dirname [info script]] ../..]]
setws $root/sw/sdk2018
if {![file exists $root/sw/sdk2018/scope_fsbl/.project]} {
 createapp -name scope_fsbl -hwproject scope_hw -proc ps7_cortexa9_0 -os standalone -lang C -app {Zynq FSBL}
}
configapp -app scope_fsbl build-config release
projects -build -type app -name scope_fsbl
set fsbl $root/sw/sdk2018/scope_fsbl/Release/scope_fsbl.elf
if {![file exists $fsbl]} {error "FSBL missing"}
file mkdir $root/boot
file copy -force $fsbl $root/boot/fsbl.elf
file copy -force $root/results/2026-10-17/scope_top.bit $root/boot/scope_top.bit
file copy -force $root/results/2026-10-17/scope.elf $root/boot/scope.elf
set f [open $root/boot/boot.bif w]
puts $f {the_ROM_image:
{
 [bootloader] fsbl.elf
 scope_top.bit
 scope.elf
}}
close $f
cd $root/boot
exec D:/Xilinx/SDK/2018.3/bin/bootgen.bat -arch zynq -image boot.bif -o BOOT.BIN -w on
if {![file exists BOOT.BIN] || [file size BOOT.BIN]>16777216} {error "Invalid boot image size"}
puts BOOT_IMAGE_BUILD_PASS
} failure]} {puts stderr "BOOT_IMAGE_BUILD_FAILED: $failure";exit 1}
exit 0
