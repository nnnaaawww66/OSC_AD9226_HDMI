param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Command=@('status'))
$ErrorActionPreference='Stop'
& 'D:\Xilinx\SDK\2018.3\bin\xsct.bat' (Join-Path $PSScriptRoot 'hw\scripts\jtag_console.tcl') @Command
