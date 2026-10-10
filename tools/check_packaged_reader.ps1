param([Parameter(Mandatory)][string]$Tag, [Parameter(Mandatory)][string]$PreviousTag)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location (Join-Path $PSScriptRoot '../app')
$Directory = Join-Path ([IO.Path]::GetTempPath()) ('papyrus-reader-' + [Guid]::NewGuid().ToString())
try {
    foreach ($Version in @($PreviousTag, $Tag)) {
        $Installer = (Resolve-Path "dist/papyrus-$Version-windows-x64-setup.exe").Path
        $Process = Start-Process $Installer -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=`"$Directory`"") -Wait -PassThru
        if ($Process.ExitCode -ne 0) { throw "Installer failed for $Version" }
    }
    $VersionKey = 'HKCU:/Software/Microsoft/Windows/CurrentVersion/Uninstall/{EE12464D-190B-4F05-B5D7-C333AE7DFA91}_is1'
    if ((Get-ItemProperty $VersionKey).DisplayVersion -ne $Tag.Substring(1)) { throw 'Upgrade did not update installed version' }
    $Shortcut = Join-Path $env:APPDATA 'Microsoft/Windows/Start Menu/Programs/Papyrus/Papyrus.lnk'
    if (-not (Test-Path $Shortcut)) { throw 'Start menu shortcut is missing' }
    python ../tools/run_packaged_smoke.py --report build/package-smoke-results/windows-installer.json -- (Join-Path $Directory 'papyrus.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Installed reader smoke failed' }
    $Uninstall = Start-Process (Join-Path $Directory 'unins000.exe') -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -Wait -PassThru
    if ($Uninstall.ExitCode -ne 0) { throw 'Uninstall failed' }
} finally {
    if (Test-Path $Directory) { Remove-Item -Recurse -Force $Directory }
}
