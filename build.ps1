param([switch]$NativeTests, [switch]$Publish)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$taskLocalDotnet = Join-Path $PSScriptRoot '.tools/dotnet/dotnet.exe'
$taskDotnet = if (Test-Path -LiteralPath $taskLocalDotnet) { $taskLocalDotnet } else { 'dotnet' }
$env:DOTNET_CLI_HOME = Join-Path $PSScriptRoot '.tools/cli-home'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
& $taskDotnet build Bento.slnx -c Release --nologo -m:1 -p:UseSharedCompilation=false
if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
if ($NativeTests) {
    & './tests/Bento.Tests/bin/Release/net10.0-windows/Bento.Tests.exe' --native
} else {
    & './tests/Bento.Tests/bin/Release/net10.0-windows/Bento.Tests.exe'
}
if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
if ($Publish) {
    & $taskDotnet publish src/Bento.UI/Bento.UI.csproj -c Release --no-restore --nologo -m:1 -p:UseSharedCompilation=false -o artifacts/Bento
    if ($LASTEXITCODE -ne 0) { throw 'Publish failed.' }
    & $taskDotnet publish src/Bento.Updater/Bento.Updater.csproj -c Release --no-restore --nologo -m:1 -p:UseSharedCompilation=false -o artifacts/Bento
    if ($LASTEXITCODE -ne 0) { throw 'Updater publish failed.' }
    $taskFiles = [ordered]@{}
    Get-ChildItem -LiteralPath './artifacts/Bento' -File | Where-Object Name -ne 'bento-release.json' | ForEach-Object { $taskFiles[$_.Name] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    # Informational/ProductVersion can contain a Git hash; the updater requires a numeric release version.
    $taskVersion = [Reflection.AssemblyName]::GetAssemblyName((Join-Path $PSScriptRoot 'artifacts/Bento/Bento.dll')).Version.ToString(3)
    [ordered]@{ AppId = 'Bento.Windows'; Version = $taskVersion; Platform = 'win-x64'; Files = $taskFiles } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath './artifacts/Bento/bento-release.json' -Encoding utf8
    Compress-Archive -Path './artifacts/Bento/*' -DestinationPath './artifacts/Bento-win-x64.zip' -Force
    [ordered]@{ AppId = 'Bento.Windows'; Version = $taskVersion; Platform = 'win-x64'; Asset = 'Bento-win-x64.zip'; Sha256 = (Get-FileHash -LiteralPath './artifacts/Bento-win-x64.zip' -Algorithm SHA256).Hash } | ConvertTo-Json | Set-Content -LiteralPath './artifacts/Bento-windows-release.json' -Encoding utf8
}
