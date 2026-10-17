$ErrorActionPreference='Stop'
$python=Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
if(-not(Test-Path -LiteralPath $python)){
 $python='D:\Anaconda\python.exe'
 if(-not(Test-Path -LiteralPath $python)){$python='python'}
}
& $python -X utf8 (Join-Path $PSScriptRoot 'app.py')
