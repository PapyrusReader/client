param([Parameter(Mandatory)][string]$Tag)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location (Join-Path $PSScriptRoot '../app')
$Installer = (Resolve-Path "dist/papyrus-$Tag-windows-x64-setup.exe").Path
$Directory = Join-Path ([IO.Path]::GetTempPath()) ('papyrus-install-' + [Guid]::NewGuid().ToString())
$UserData = Join-Path $env:APPDATA 'com.papyrus/papyrus'
New-Item -ItemType Directory -Force $UserData | Out-Null
$Sentinel = Join-Path $UserData 'packaging-preserve-test.txt'
if (Test-Path $Sentinel) { throw 'Packaging test sentinel already exists' }
Set-Content $Sentinel 'preserve-user-data'
try {
    foreach ($Pass in @(1, 2)) {
        $Process = Start-Process $Installer -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=`"$Directory`"") -Wait -PassThru
        if ($Process.ExitCode -ne 0) { throw "Installer failed on pass $Pass with $($Process.ExitCode)" }
        foreach ($Name in @('papyrus.exe', 'flutter_windows.dll', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'data/app.so')) {
            if (-not (Test-Path (Join-Path $Directory $Name))) { throw "Missing packaged file: $Name" }
        }
    }
    $App = Start-Process (Join-Path $Directory 'papyrus.exe') -PassThru
    Start-Sleep -Seconds 15
    if ($App.HasExited) { throw "Installed app exited during launch check: $($App.ExitCode)" }
    Stop-Process -Id $App.Id
    $WebViewSdk = (Resolve-Path 'windows/flutter/ephemeral/.plugin_symlinks/desktop_webview_window/windows').Path
    $SmokeBuild = Join-Path $Directory 'packaging-smoke'
    & cmake -S ../packaging/windows/smoke -B $SmokeBuild -A x64 "-DWEBVIEW_SDK=$WebViewSdk"
    if ($LASTEXITCODE -ne 0) { throw 'WebView2 smoke configuration failed' }
    & cmake --build $SmokeBuild --config Release
    if ($LASTEXITCODE -ne 0) { throw 'WebView2 smoke compilation failed' }
    & (Join-Path $SmokeBuild 'Release/papyrus_webview_smoke.exe') (Join-Path $Directory 'Webview2Loader.dll') (Join-Path $SmokeBuild 'profile')
    if ($LASTEXITCODE -ne 0) { throw 'Installed WebView2 runtime failed HTML/canvas/JavaScript rendering' }
    Remove-Item -Recurse -Force $SmokeBuild
    $Uninstall = Start-Process (Join-Path $Directory 'unins000.exe') -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -Wait -PassThru
    if ($Uninstall.ExitCode -ne 0) { throw 'Uninstall failed' }
    if (Test-Path (Join-Path $Directory 'papyrus.exe')) { throw 'Uninstall left the application executable' }
    if ((Get-Content $Sentinel) -ne 'preserve-user-data') { throw 'Installer changed user data' }
} finally {
    if (Test-Path $Directory) { Remove-Item -Recurse -Force $Directory }
    Remove-Item -Force $Sentinel
}
