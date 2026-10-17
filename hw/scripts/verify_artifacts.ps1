param([string]$Root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
$folder=Join-Path $Root 'results/2026-10-17'
$manifest=Get-Content -LiteralPath (Join-Path $folder 'release_artifacts.json') -Raw | ConvertFrom-Json
foreach($entry in $manifest.files){
 if([IO.Path]::GetFileName($entry.name) -cne $entry.name){throw 'Invalid release filename'}
 $path=Join-Path $folder $entry.name
 if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $entry.sha256){throw "Release artifact changed or mismatched: $($entry.name). Rebuild and reseal before programming."}
}
Write-Output "RELEASE_ARTIFACTS_VERIFIED rtl=$($manifest.rtl_revision)"
