param([switch]$RestoreOriginal)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$sdk='D:\Xilinx\SDK\2018.3\bin'
if($RestoreOriginal){
 $image=Join-Path $root 'backup\qspi_before_dac_20261017\qspi_16MiB.bin'
 $manifest=Get-Content (Join-Path $root 'backup\qspi_before_dac_20261017\manifest.json') -Raw | ConvertFrom-Json
 if((Get-FileHash -LiteralPath $image).Hash -ine $manifest.sha256){throw 'Original Flash backup hash mismatch'}
}else{
 & (Join-Path $root 'hw\scripts\verify_artifacts.ps1') -Root $root
 $manifest=Get-Content (Join-Path $root 'boot\manifest.json') -Raw | ConvertFrom-Json
 foreach($entry in $manifest.files){
  if([IO.Path]::GetFileName($entry.name) -cne $entry.name){throw 'Invalid boot manifest filename'}
  if((Get-FileHash -LiteralPath (Join-Path $root ('boot\'+$entry.name))).Hash -ine $entry.sha256){throw "Boot artifact changed: $($entry.name)"}
 }
 $image=Join-Path $root 'boot\BOOT.BIN'
 if(-not(Test-Path -LiteralPath (Join-Path $root 'backup\qspi_before_dac_20261017\manifest.json'))){throw 'Original Flash backup must be completed first'}
}
$log=Join-Path $root 'boot\flash_program.log'
& (Join-Path $sdk 'program_flash.bat') -f $image -offset 0 -fsbl (Join-Path $root 'boot\fsbl.elf') -flash_type qspi-x4-single -blank_check -verify -target_name 'jsn-JTAG-HS2-201706300081-4ba00477-0' -url 'tcp:127.0.0.1:3121' 2>&1 | Tee-Object -FilePath $log
$result=Get-Content -LiteralPath $log -Raw
if($LASTEXITCODE -ne 0 -or $result -notmatch 'Flash Operation Successful'){throw 'Flash programming/verification not confirmed; inspect boot\flash_program.log'}
Write-Host 'FLASH_PROGRAM_VERIFY_PASS. Power off, set BOOT jumper to the middle QSPI pair, then power on.'
