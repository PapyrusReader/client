function Assert-PackageFiles {
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string]$Bundle)
    foreach ($Name in @('papyrus.exe', 'flutter_windows.dll', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'Webview2Loader.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin')) {
        if (-not (Test-Path (Join-Path $Directory $Name))) { throw "Missing packaged file: $Name" }
    }

    foreach ($Asset in (Get-ChildItem (Join-Path $PSScriptRoot '../app/assets/images') -File -Recurse)) {
        $AppDirectory = (Resolve-Path (Join-Path $PSScriptRoot '../app')).Path
        $Relative = [IO.Path]::GetRelativePath($AppDirectory, $Asset.FullName)
        if (-not (Test-Path (Join-Path $Directory "data/flutter_assets/$Relative"))) {
            throw "Missing application image: $Relative"
        }
    }

    foreach ($File in (Get-ChildItem $Bundle -File -Recurse)) {
        $Relative = [IO.Path]::GetRelativePath($Bundle, $File.FullName)
        $PackagedFile = Join-Path $Directory $Relative
        if (-not (Test-Path $PackagedFile)) { throw "Missing bundle file: $Relative" }
        if ((Get-FileHash $File.FullName).Hash -ne (Get-FileHash $PackagedFile).Hash) {
            throw "Packaged bundle file differs: $Relative"
        }
    }

    $Version = (Get-Item (Join-Path $Directory 'papyrus.exe')).VersionInfo
    if ($Version.FileDescription -cne 'Papyrus') { throw 'Executable description must be Papyrus' }
    if ($Version.CompanyName -cne 'com.papyrus' -or $Version.ProductName -cne 'papyrus') {
        throw 'Executable metadata changed the Windows user-data identity'
    }
}

function Assert-PapyrusLaunch {
    param([Parameter(Mandatory)][string]$Directory)
    $App = Start-Process (Join-Path $Directory 'papyrus.exe') -WorkingDirectory $Directory -PassThru

    try {
        $Deadline = [DateTime]::UtcNow.AddSeconds(30)

        do {
            Start-Sleep -Seconds 1
            $App.Refresh()
            if ($App.HasExited) { throw "Packaged app exited during launch check: $($App.ExitCode)" }
            if ($App.MainWindowHandle -ne 0) { break }
        } while ([DateTime]::UtcNow -lt $Deadline)

        if ($App.MainWindowTitle -cne 'Papyrus') {
            throw "Expected Papyrus window title, got: $($App.MainWindowTitle)"
        }

        Start-Sleep -Seconds 5
        $App.Refresh()
        if ($App.HasExited) { throw 'Packaged app exited after creating its window' }
    } finally {
        if (-not $App.HasExited) {
            Stop-Process -Id $App.Id
            $App.WaitForExit()
        }

        $App.Dispose()
    }
}

function Remove-TestDirectory {
    param([Parameter(Mandatory)][string]$Path)
    for ($Attempt = 0; $Attempt -lt 30; $Attempt++) {
        if (-not (Test-Path $Path)) { return }
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return
        } catch {
            if ($Attempt -eq 29) { throw }
            Start-Sleep -Seconds 1
        }
    }
}
