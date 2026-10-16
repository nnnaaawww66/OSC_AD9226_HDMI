$ErrorActionPreference='Stop'
$root=$PSScriptRoot
foreach($name in 'scope_top.bit','scope_top.hdf','scope.elf','scope_diag.elf','ps7_init.tcl'){
 if(-not(Test-Path -LiteralPath (Join-Path $root "results\2026-10-17\$name"))){throw "Missing qualified output: $name"}
}
$programStarted=Get-Date
& 'D:\Xilinx\SDK\2018.3\bin\xsct.bat' (Join-Path $root 'hw\scripts\program.tcl')
if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath (Join-Path $root 'results\2026-10-17\program.ok')) -or (Get-Item -LiteralPath (Join-Path $root 'results\2026-10-17\program.ok')).LastWriteTime -lt $programStarted){throw 'JTAG program/start failed; inspect target connection'}
