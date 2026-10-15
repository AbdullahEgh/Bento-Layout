$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$taskBento = Join-Path $PSScriptRoot 'src/Bento.UI/bin/Release/net10.0-windows/Bento.exe'
if (-not (Test-Path -LiteralPath $taskBento)) { & './build.ps1' }
Start-Process -FilePath $taskBento -WindowStyle Hidden
