param([string]$Root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
& (Join-Path $Root 'hw\scripts\verify_artifacts.ps1') -Root $Root
$entries=@()
foreach($name in 'BOOT.BIN','fsbl.elf','scope_top.bit','scope.elf','boot.bif'){
 $path=Join-Path $Root ('boot\'+$name)
 $entries+=@{name=$name;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $path).Length}
}
if((Get-FileHash (Join-Path $Root 'boot\scope_top.bit')).Hash -ine (Get-FileHash (Join-Path $Root 'results\2026-10-17\scope_top.bit')).Hash){throw 'Boot bitstream differs from qualified release'}
if((Get-FileHash (Join-Path $Root 'boot\scope.elf')).Hash -ine (Get-FileHash (Join-Path $Root 'results\2026-10-17\scope.elf')).Hash){throw 'Boot application differs from qualified release'}
@{sealed_at=(Get-Date -Format o);flash='W25Q128JV single x4 16MiB';files=$entries} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Root 'boot\manifest.json') -Encoding utf8
Write-Output 'BOOT_SEAL_PASS'
