param([string]$Root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
$folder=Join-Path $Root 'results/2026-10-17'
$required=@('scope_top.bit','scope_top.hdf','scope_top.ltx','scope.elf','scope_diag.elf','ps7_init.tcl','build_revision.txt','hardware_build.ok','sdk_build.ok')
$manifest=Get-Content -LiteralPath (Join-Path $folder 'release_artifacts.json') -Raw | ConvertFrom-Json
if($manifest.files.Count -ne $required.Count -or (Compare-Object ($required|Sort-Object) ($manifest.files.name|Sort-Object))){throw 'Release manifest is incomplete or has duplicate/unexpected entries'}
foreach($entry in $manifest.files){
 if([IO.Path]::GetFileName($entry.name) -cne $entry.name){throw 'Invalid release filename'}
 $path=Join-Path $folder $entry.name
 if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $entry.sha256){throw "Release artifact changed or mismatched: $($entry.name). Rebuild and reseal before programming."}
}
Write-Output "RELEASE_ARTIFACTS_VERIFIED rtl=$($manifest.rtl_revision)"
