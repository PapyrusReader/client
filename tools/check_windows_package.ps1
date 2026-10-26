param([Parameter(Mandatory)][string]$Tag, [switch]$RequireMissingRuntime)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'windows_test_helpers.ps1')
Set-Location (Join-Path $PSScriptRoot '../app')
if ($RequireMissingRuntime) {
    if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') {
        throw 'Runtime isolation is restricted to disposable GitHub-hosted runners'
    }

    # Evergreen is an OS component on current runners and refuses uninstallation.
    # Quarantine both binaries and registrations, not just the detection key.
    $Quarantine = Join-Path ([IO.Path]::GetTempPath()) ('papyrus-webview-' + [Guid]::NewGuid().ToString())
    New-Item -ItemType Directory $Quarantine | Out-Null
    Get-Process msedgewebview2 -ErrorAction SilentlyContinue | Stop-Process -Force
    $RuntimeRoots = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft/EdgeWebView'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft/EdgeWebView')
    )
    foreach ($RuntimeRoot in $RuntimeRoots) {
        if (Test-Path $RuntimeRoot) {
            Move-Item $RuntimeRoot (Join-Path $Quarantine ([Guid]::NewGuid().ToString()))
        }
    }
    foreach ($Root in @('HKLM:/Software/WOW6432Node/Microsoft/EdgeUpdate', 'HKCU:/Software/Microsoft/EdgeUpdate')) {
        foreach ($Registration in @('Clients', 'ClientState', 'ClientStateMedium')) {
            $Key = "$Root/$Registration/{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
            if (Test-Path $Key) { Remove-Item $Key -Recurse -Force }
        }
    }
    Write-Output 'Preinstalled WebView2 binaries and registrations isolated on disposable runner'
    $ClientKey = 'Software/Microsoft/EdgeUpdate/Clients/{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    foreach ($Key in @("HKLM:/Software/WOW6432Node/Microsoft/EdgeUpdate/Clients/{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}", "HKCU:/$ClientKey")) {
        $Runtime = Get-ItemProperty $Key -Name pv -ErrorAction SilentlyContinue
        if ($null -ne $Runtime -and $Runtime.pv -and $Runtime.pv -ne '0.0.0.0') {
            throw 'WebView2 remains installed; missing-runtime coverage cannot be claimed'
        }
    }
    foreach ($RuntimeRoot in $RuntimeRoots) {
        if (Get-ChildItem "$RuntimeRoot/Application/*/msedgewebview2.exe" -ErrorAction SilentlyContinue) {
            throw 'WebView2 executable remains after isolation'
        }
    }
}
$Installer = (Resolve-Path "dist/papyrus-$Tag-windows-x64-setup.exe").Path
$Bundle = (Resolve-Path 'build/windows/x64/runner/Release').Path
$Directory = Join-Path ([IO.Path]::GetTempPath()) ('papyrus-install-' + [Guid]::NewGuid().ToString())
$DesktopShortcut = Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'Papyrus.lnk'
$StartMenuShortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Papyrus/Papyrus.lnk'

foreach ($Shortcut in @($DesktopShortcut, $StartMenuShortcut)) {
    if (Test-Path $Shortcut) { throw "Packaging test would overwrite an existing shortcut: $Shortcut" }
}

$UserData = Join-Path $env:APPDATA 'com.papyrus/papyrus'
New-Item -ItemType Directory -Force $UserData | Out-Null
$Sentinel = Join-Path $UserData 'packaging-preserve-test.txt'
if (Test-Path $Sentinel) { throw 'Packaging test sentinel already exists' }
Set-Content $Sentinel 'preserve-user-data'
try {
    foreach ($Pass in @(1, 2, 3)) {
        $Log = Join-Path ([IO.Path]::GetTempPath()) ('papyrus-install-' + [Guid]::NewGuid().ToString() + '.log')
        $Arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=`"$Log`"", "/DIR=`"$Directory`"")
        if ($Pass -eq 1) { $Arguments += '/TASKS=!desktopicon' }
        if ($Pass -eq 2) { $Arguments += '/TASKS=desktopicon' }
        $Process = Start-Process $Installer -ArgumentList $Arguments -Wait -PassThru
        if ($Process.ExitCode -ne 0) { throw "Installer failed on pass $Pass with $($Process.ExitCode)" }
        $ExpectedRuntime = 'Papyrus: existing WebView2 runtime retained'
        if ($Pass -eq 1 -and $RequireMissingRuntime) { $ExpectedRuntime = 'Papyrus: installing missing WebView2 runtime' }
        if (($Pass -ge 2 -or $RequireMissingRuntime) -and -not (Select-String -Path $Log -SimpleMatch $ExpectedRuntime)) {
            throw "Installer did not verify the expected runtime path: $ExpectedRuntime"
        }
        Write-Output "Installer pass $Pass runtime validation: $ExpectedRuntime"
        Remove-Item $Log
        Assert-PackageFiles -Directory $Directory -Bundle $Bundle

        if ((Test-Path $DesktopShortcut) -ne ($Pass -ge 2)) {
            throw "Desktop shortcut did not respect the selected task on pass $Pass"
        }

        $Shell = New-Object -ComObject WScript.Shell
        $Shortcuts = @($StartMenuShortcut)
        if ($Pass -ge 2) { $Shortcuts += $DesktopShortcut }

        foreach ($Shortcut in $Shortcuts) {
            if (-not (Test-Path $Shortcut)) { throw "Missing shortcut: $Shortcut" }
            if ($Shell.CreateShortcut($Shortcut).TargetPath -ne (Join-Path $Directory 'papyrus.exe')) {
                throw "Shortcut points to the wrong executable: $Shortcut"
            }
        }
    }
    Assert-PapyrusLaunch -Directory $Directory
    $WebViewSdk = (Resolve-Path 'windows/flutter/ephemeral/.plugin_symlinks/desktop_webview_window/windows').Path
    $SmokeBuild = Join-Path $Directory 'packaging-smoke'
    & cmake -S ../packaging/windows/smoke -B $SmokeBuild -A x64 "-DWEBVIEW_SDK=$WebViewSdk"
    if ($LASTEXITCODE -ne 0) { throw 'WebView2 smoke configuration failed' }
    & cmake --build $SmokeBuild --config Release
    if ($LASTEXITCODE -ne 0) { throw 'WebView2 smoke compilation failed' }
    & (Join-Path $SmokeBuild 'Release/papyrus_webview_smoke.exe') (Join-Path $Directory 'Webview2Loader.dll') (Join-Path $SmokeBuild 'profile')
    if ($LASTEXITCODE -ne 0) { throw 'Installed WebView2 runtime failed HTML/canvas/JavaScript rendering' }
    Remove-TestDirectory $SmokeBuild
    $Uninstall = Start-Process (Join-Path $Directory 'unins000.exe') -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -Wait -PassThru
    if ($Uninstall.ExitCode -ne 0) { throw 'Uninstall failed' }
    if (Test-Path (Join-Path $Directory 'papyrus.exe')) { throw 'Uninstall left the application executable' }
    foreach ($Shortcut in @($DesktopShortcut, $StartMenuShortcut)) {
        if (Test-Path $Shortcut) { throw "Uninstall left a shortcut: $Shortcut" }
    }
    if ((Get-Content $Sentinel) -ne 'preserve-user-data') { throw 'Installer changed user data' }
} finally {
    Remove-TestDirectory $Directory
    Remove-Item -Force $Sentinel
    foreach ($Shortcut in @($DesktopShortcut, $StartMenuShortcut)) {
        if (Test-Path $Shortcut) { Remove-Item -Force $Shortcut }
    }
}
