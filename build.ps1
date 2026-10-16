param([switch]$Recreate)
$ErrorActionPreference='Stop'
$projectRoot=$PSScriptRoot
$vivado='D:\Xilinx\Vivado\2018.3\bin\vivado.bat'
$xsct='D:\Xilinx\SDK\2018.3\bin\xsct.bat'
if($Recreate){
 if(Test-Path -LiteralPath (Join-Path $projectRoot 'OSC_ad9226_hdmi.srcs')){throw 'For a clean reconstruction, extract the source archive to a new directory, then run -Recreate.'}
 & $vivado -mode batch -nojournal -source (Join-Path $projectRoot 'hw\scripts\create_project.tcl') -log (Join-Path $projectRoot 'results\2026-10-17\recreate.log')
 if($LASTEXITCODE -ne 0){throw 'Vivado reconstruction failed'}
}
& $vivado -mode batch -nojournal -source (Join-Path $projectRoot 'hw\scripts\build_with_fallback.tcl') -log (Join-Path $projectRoot 'results\2026-10-17\one_click_build.log')
if($LASTEXITCODE -ne 0){throw 'Digital timing/DRC build failed; no approved bitstream'}
& $xsct (Join-Path $projectRoot 'sw\scripts\release_sdk.tcl')
if($LASTEXITCODE -ne 0){throw 'SDK build failed'}
Write-Host 'Build complete. Inspect Acceptance.json before claiming hardware qualification.'
