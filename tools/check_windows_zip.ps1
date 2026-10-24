param([Parameter(Mandatory)][string]$Tag, [switch]$ReaderSmoke)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'windows_test_helpers.ps1')
Set-Location (Join-Path $PSScriptRoot '../app')
$Bundle = (Resolve-Path 'build/windows/x64/runner/Release').Path
$Archive = (Resolve-Path "dist/papyrus-$Tag-windows-x64.zip").Path
$Directory = Join-Path ([IO.Path]::GetTempPath()) ('papyrus-zip-' + [Guid]::NewGuid().ToString())

try {
    Expand-Archive -LiteralPath $Archive -DestinationPath $Directory
    Assert-PackageFiles -Directory $Directory -Bundle $Bundle

    if ($ReaderSmoke) {
        python ../tools/run_packaged_smoke.py --report build/package-smoke-results/windows-zip.json -- (Join-Path $Directory 'papyrus.exe')
        if ($LASTEXITCODE -ne 0) { throw 'ZIP reader smoke failed' }
    } else {
        Assert-PapyrusLaunch -Directory $Directory
    }
} finally {
    Remove-TestDirectory $Directory
}
