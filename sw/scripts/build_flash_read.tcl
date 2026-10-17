if {[catch {
set root [file normalize [file join [file dirname [info script]] ../..]]
setws $root/sw/sdk2018
if {![file exists $root/sw/sdk2018/scope_flash_read/.project]} {
 createapp -name scope_flash_read -hwproject scope_hw -proc ps7_cortexa9_0 -os standalone -bsp scope_bsp -lang C -app {Empty Application}
}
file copy -force $root/sw/flash_read/main.c $root/sw/sdk2018/scope_flash_read/src/
file copy -force $root/sw/src/lscript.ld $root/sw/sdk2018/scope_flash_read/src/
configapp -app scope_flash_read build-config release
projects -build -type app -name scope_flash_read
file copy -force $root/sw/sdk2018/scope_flash_read/Release/scope_flash_read.elf $root/boot/flash_read.elf
puts FLASH_READ_BUILD_PASS
} failure]} {puts stderr "FLASH_READ_BUILD_FAILED: $failure";exit 1}
exit 0
