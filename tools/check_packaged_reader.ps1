param([Parameter(Mandatory)][string]$Tag, [Parameter(Mandatory)][string]$PreviousTag)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'windows_test_helpers.ps1')
Set-Location (Join-Path $PSScriptRoot '../app')
$Directory = Join-Path ([IO.Path]::GetTempPath()) ('papyrus reader ' + [Guid]::NewGuid().ToString())
$Reports = Join-Path $PWD 'build/package-smoke-results'
New-Item -ItemType Directory -Path $Reports -Force | Out-Null
function Install-TestPackage([string]$Version) {
    $Installer = (Resolve-Path "dist/papyrus-$Version-windows-x64-setup.exe").Path
    $Process = Start-Process $Installer -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=`"$Directory`"") -Wait -PassThru
    if ($Process.ExitCode -ne 0) { throw "Installer failed for $Version" }
}
function Install-TestUpdate([string]$Version) {
    $Download = Join-Path $Directory 'update download'
    New-Item -ItemType Directory -Path $Download | Out-Null
    $Installer = Join-Path $Download 'setup.exe'
    Copy-Item "dist/papyrus-$Version-windows-x64-setup.exe" $Installer
    $Checksum = (Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash.ToLowerInvariant()
    $Helper = (Resolve-Path 'assets/updates/install_windows.ps1').Path
    $RejectedLog = Join-Path $Download 'update.log'
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Helper `
        -ParentId ([int]::MaxValue) -Installer $Installer -Checksum ('0' * 64) -InstallDirectory $Directory

    if ($LASTEXITCODE -ne 1 -or -not (Test-Path $Installer) -or
        -not (Select-String -LiteralPath $RejectedLog -SimpleMatch 'Update checksum changed after download.')) {
        throw 'Updater did not reject an invalid checksum before installation'
    }

    Copy-Item $RejectedLog (Join-Path $Reports 'windows-updater-rejected.log')
    Remove-Item $RejectedLog
    $Report = Join-Path $PWD 'build/package-smoke-results/windows-updater.json'
    Remove-Item -LiteralPath $Report -ErrorAction SilentlyContinue
    $env:PAPYRUS_PERSISTENCE_PHASE = 'verify'
    $env:PAPYRUS_SMOKE_REPORT = $Report
    $Parent = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 3') -PassThru
    $Arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', "`"$Helper`"", '-ParentId', $Parent.Id,
        '-Installer', "`"$Installer`"", '-Checksum', $Checksum, '-InstallDirectory', "`"$Directory`"")
    $Updater = Start-Process powershell.exe -ArgumentList $Arguments -PassThru -NoNewWindow `
        -RedirectStandardOutput (Join-Path $Reports 'windows-updater-stdout.log') `
        -RedirectStandardError (Join-Path $Reports 'windows-updater-stderr.log')
    Start-Sleep -Milliseconds 500
    if ($Updater.HasExited) { throw 'Updater did not wait for normal app exit' }
    if (-not $Updater.WaitForExit(120000)) { throw 'Updater timed out' }
    if ($Updater.ExitCode -ne 0) {
        Get-Content -LiteralPath (Join-Path $Download 'update.log') -ErrorAction SilentlyContinue | Write-Host
        throw "Updater failed with exit code $($Updater.ExitCode)"
    }
    $Deadline = [DateTime]::UtcNow.AddSeconds(300)
    while (-not (Test-Path $Report) -and [DateTime]::UtcNow -lt $Deadline) { Start-Sleep -Seconds 1 }
    if (-not (Test-Path $Report)) { throw "Updater did not relaunch the reader. See $Download/update.log" }
    $Result = Get-Content -LiteralPath $Report -Raw | ConvertFrom-Json
    if ($Result.passed -ne $true) { throw 'Updater did not preserve the seeded library' }
    $Relaunched = Get-Process papyrus -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq (Join-Path $Directory 'papyrus.exe') }
    foreach ($Process in $Relaunched) {
        if (-not $Process.WaitForExit(30000)) { throw 'Relaunched reader did not finish its test' }
    }
    Remove-Item Env:PAPYRUS_SMOKE_REPORT
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
    Install-TestUpdate $Tag
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
    Remove-Item Env:PAPYRUS_SMOKE_REPORT -ErrorAction SilentlyContinue
    Remove-Item Env:PAPYRUS_PERSISTENCE_PHASE -ErrorAction SilentlyContinue
    Remove-Item Env:PAPYRUS_PERSISTENCE_SESSION -ErrorAction SilentlyContinue
    $UpdateLog = Join-Path $Directory 'update download/update.log'
    if (Test-Path $UpdateLog) { Copy-Item $UpdateLog (Join-Path $Reports 'windows-updater-install.log') }
    Remove-TestDirectory $Directory
}
