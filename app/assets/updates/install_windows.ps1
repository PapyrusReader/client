param(
    [Parameter(Mandatory)][int]$ParentId,
    [Parameter(Mandatory)][string]$Installer,
    [Parameter(Mandatory)][string]$Checksum,
    [Parameter(Mandatory)][string]$InstallDirectory
)
$ErrorActionPreference = 'Stop'
$Log = Join-Path (Split-Path $Installer) 'update.log'
try {
    # Wait for the user's normal shutdown, preserving pending library writes.
    $Parent = Get-Process -Id $ParentId -ErrorAction SilentlyContinue
    if ($Parent -and -not $Parent.WaitForExit(86400000)) { throw 'Update expired while Papyrus was still running.' }
    if ((Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Checksum) {
        throw 'Update checksum changed after download.'
    }
    $Arguments = @('/SP-', '/SILENT', '/NORESTART', '/NOCLOSEAPPLICATIONS', '/SUPPRESSMSGBOXES', "/DIR=`"$InstallDirectory`"", "/LOG=`"$Log`"")
    $Setup = Start-Process -FilePath $Installer -ArgumentList $Arguments -PassThru -Wait
    if ($Setup.ExitCode -ne 0) { throw "Installer failed with exit code $($Setup.ExitCode). See $Log" }
    Start-Process -FilePath (Join-Path $InstallDirectory 'papyrus.exe')
    Remove-Item -LiteralPath $Installer
} catch {
    $_ | Out-String | Add-Content -LiteralPath $Log
    # Keep the verified installer and diagnostics for a manual retry.
}
