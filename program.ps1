$ErrorActionPreference='Stop'
$root=$PSScriptRoot
foreach($name in 'scope_top.bit','scope_top.hdf'){
 if(-not(Test-Path -LiteralPath (Join-Path $root "results\2026-10-17\$name"))){throw "Missing qualified output: $name"}
}
& 'D:\Xilinx\SDK\2018.3\bin\xsct.bat' (Join-Path $root 'hw\scripts\program.tcl')
if($LASTEXITCODE -ne 0){throw 'JTAG program/start failed; inspect target connection'}
