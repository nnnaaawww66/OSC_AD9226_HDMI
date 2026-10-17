param([string]$Python='python')
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
& $Python -X utf8 -m PyInstaller --version
if($LASTEXITCODE -ne 0){throw 'PyInstaller is required in the selected Python environment'}
& $Python -X utf8 -m PyInstaller --noconfirm --windowed --onedir --name Z7_LAB --distpath (Join-Path $root 'dist') --workpath (Join-Path $root 'build') --specpath (Join-Path $root 'build') --exclude-module matplotlib --exclude-module pandas --exclude-module torch --exclude-module tensorflow (Join-Path $root 'app.py')
if($LASTEXITCODE -ne 0){throw 'Host executable build failed'}
Write-Host 'Build complete: copy the entire host/dist/Z7_LAB folder, including _internal.'
