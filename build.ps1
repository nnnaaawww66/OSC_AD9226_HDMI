param([switch]$Recreate)
$ErrorActionPreference='Stop'
$projectRoot=$PSScriptRoot
$vivado='D:\Xilinx\Vivado\2018.3\bin\vivado.bat'
$xsct='D:\Xilinx\SDK\2018.3\bin\xsct.bat'
New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot 'results\2026-10-17') | Out-Null
if($Recreate){
 if(Test-Path -LiteralPath (Join-Path $projectRoot 'OSC_ad9226_hdmi.srcs')){throw 'For a clean reconstruction, extract the source archive to a new directory, then run -Recreate.'}
 & $vivado -mode batch -nojournal -source (Join-Path $projectRoot 'hw\scripts\create_project.tcl') -log (Join-Path $projectRoot 'results\2026-10-17\recreate.log')
 if($LASTEXITCODE -ne 0){throw 'Vivado reconstruction failed'}
}
& $vivado -mode batch -nojournal -source (Join-Path $projectRoot 'hw\scripts\build_with_fallback.tcl') -log (Join-Path $projectRoot 'results\2026-10-17\one_click_build.log')
if($LASTEXITCODE -ne 0){throw 'Digital timing/DRC build failed; no approved bitstream'}
$sdkStarted=Get-Date
& $xsct (Join-Path $projectRoot 'sw\scripts\release_sdk.tcl')
if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath (Join-Path $projectRoot 'results\2026-10-17\sdk_build.ok')) -or (Get-Item -LiteralPath (Join-Path $projectRoot 'results\2026-10-17\sdk_build.ok')).LastWriteTime -lt $sdkStarted){throw 'SDK build failed; inspect compiler output'}
& (Join-Path $projectRoot 'hw/scripts/seal_release.ps1') -Root $projectRoot
$bootStarted=Get-Date
& $xsct (Join-Path $projectRoot 'sw\scripts\build_boot.tcl')
if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath (Join-Path $projectRoot 'boot\BOOT.BIN')) -or (Get-Item -LiteralPath (Join-Path $projectRoot 'boot\BOOT.BIN')).LastWriteTime -lt $bootStarted){throw 'Boot image build failed'}
& (Join-Path $projectRoot 'hw\scripts\seal_boot.ps1') -Root $projectRoot
Write-Host 'Build complete. Inspect Acceptance.json before claiming hardware qualification.'
