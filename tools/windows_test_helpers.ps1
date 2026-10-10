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
