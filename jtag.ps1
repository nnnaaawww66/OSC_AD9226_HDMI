param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Command=@('status'))
$ErrorActionPreference='Stop'
$reply=& 'D:\Xilinx\SDK\2018.3\bin\xsct.bat' (Join-Path $PSScriptRoot 'hw\scripts\jtag_console.tcl') @Command 2>&1
$reply | Write-Output
if(-not($reply -match '^JTAG_COMMAND_PASS$')){throw 'JTAG command failed; inspect firmware response'}
