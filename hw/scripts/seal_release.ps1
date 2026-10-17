param([string]$Root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
$folder=Join-Path $Root 'results/2026-10-17'
if(-not(Test-Path -LiteralPath (Join-Path $folder 'hardware_build.ok'))){throw 'No hardware timing/DRC/CDC success marker'}
if((Get-Item -LiteralPath (Join-Path $folder 'sdk_build.ok')).LastWriteTime -lt (Get-Item -LiteralPath (Join-Path $folder 'scope_top.hdf')).LastWriteTime){throw 'SDK must be rebuilt/updated against the latest hardware export'}
$entries=@()
foreach($name in 'scope_top.bit','scope_top.hdf','scope_top.ltx','scope.elf','scope_diag.elf','ps7_init.tcl','build_revision.txt','hardware_build.ok','sdk_build.ok'){
 $path=Join-Path $folder $name
 $entries+=@{name=$name;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $path).Length}
}
@{sealed_at=(Get-Date -Format o);rtl_revision=(Get-Content -LiteralPath (Join-Path $folder 'build_revision.txt') -Raw).Trim();files=$entries} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $folder 'release_artifacts.json') -Encoding utf8
Write-Output 'RELEASE_SEAL_PASS'
