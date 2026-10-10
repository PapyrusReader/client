param([Parameter(Mandatory)][string]$Tag, [Parameter(Mandatory)][string]$PreviousTag)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'windows_test_helpers.ps1')
Set-Location (Join-Path $PSScriptRoot '../app')
$Directory = Join-Path ([IO.Path]::GetTempPath()) ('papyrus-reader-' + [Guid]::NewGuid().ToString())
function Install-TestPackage([string]$Version) {
    $Installer = (Resolve-Path "dist/papyrus-$Version-windows-x64-setup.exe").Path
    $Process = Start-Process $Installer -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=`"$Directory`"") -Wait -PassThru
    if ($Process.ExitCode -ne 0) { throw "Installer failed for $Version" }
}
function Uninstall-TestPackage {
    $Uninstall = Start-Process (Join-Path $Directory 'unins000.exe') -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -Wait -PassThru
    if ($Uninstall.ExitCode -ne 0) { throw 'Uninstall failed' }
    if (Test-Path (Join-Path $Directory 'papyrus.exe')) { throw 'Uninstall left the executable' }
}
function Test-Persistence([string]$Phase, [string]$ReportName) {
    $env:PAPYRUS_PERSISTENCE_PHASE = $Phase
    python ../tools/run_packaged_smoke.py --report "build/package-smoke-results/$ReportName.json" -- (Join-Path $Directory 'papyrus.exe')
    if ($LASTEXITCODE -ne 0) { throw "Persistence validation failed: $ReportName" }
}
try {
    $env:PAPYRUS_PERSISTENCE_SESSION = [Guid]::NewGuid().ToString()
    Install-TestPackage $PreviousTag
    Test-Persistence 'seed' 'windows-persistence-seed'
    Install-TestPackage $Tag
    $VersionKey = 'HKCU:/Software/Microsoft/Windows/CurrentVersion/Uninstall/{EE12464D-190B-4F05-B5D7-C333AE7DFA91}_is1'
    if ((Get-ItemProperty $VersionKey).DisplayVersion -ne $Tag.Substring(1)) { throw 'Upgrade did not update installed version' }
    $Shortcut = Join-Path $env:APPDATA 'Microsoft/Windows/Start Menu/Programs/Papyrus/Papyrus.lnk'
    if (-not (Test-Path $Shortcut)) { throw 'Start menu shortcut is missing' }
    Test-Persistence 'verify' 'windows-persistence-upgrade'
    Uninstall-TestPackage
    if (Test-Path $Shortcut) { throw 'Uninstall left the Start menu shortcut' }
    Install-TestPackage $Tag
    Test-Persistence 'verify-and-clean' 'windows-persistence-reinstall'
    Remove-Item Env:PAPYRUS_PERSISTENCE_PHASE
    Remove-Item Env:PAPYRUS_PERSISTENCE_SESSION
    python ../tools/run_packaged_smoke.py --report build/package-smoke-results/windows-installer.json -- (Join-Path $Directory 'papyrus.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Installed reader smoke failed' }
    Uninstall-TestPackage
} finally {
    Remove-Item Env:PAPYRUS_PERSISTENCE_PHASE -ErrorAction SilentlyContinue
    Remove-Item Env:PAPYRUS_PERSISTENCE_SESSION -ErrorAction SilentlyContinue
    Remove-TestDirectory $Directory
}
