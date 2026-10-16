set root D:/Xilinx/Projects/OSC_ad9226_hdmi
setws $root/sw/sdk2018
createapp -name scope_diag -hwproject scope_hw -proc ps7_cortexa9_0 -os standalone -bsp scope_bsp -lang C -app {Empty Application}
importsources -name scope_diag -path $root/sw/diag
set ld $root/sw/sdk2018/scope_diag/src/lscript.ld
set f [open $ld r];set txt [read $f];close $f
set txt [string map {"> ps7_ddr_0" "> ps7_ram_0"} $txt]
set f [open $ld w];puts $f $txt;close $f
file copy -force $ld $root/sw/diag/lscript.ld
configapp -app scope_diag build-config release
projects -build -type app -name scope_diag
exit
