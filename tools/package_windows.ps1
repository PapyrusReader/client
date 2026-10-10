param([Parameter(Mandatory)][string]$Tag)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($Tag -notmatch '^v([0-9]+\.[0-9]+\.[0-9]+)\+([1-9][0-9]*)$') { throw 'Invalid release tag' }
$Version = $Matches[1]
$BuildNumber = $Matches[2]
Set-Location (Join-Path $PSScriptRoot '../app')
$Bundle = (Resolve-Path 'build/windows/x64/runner/Release').Path
$Dist = Join-Path $PWD 'dist'
New-Item -ItemType Directory -Force $Dist | Out-Null
$Temporary = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
New-Item -ItemType Directory $Temporary | Out-Null
try {
    $VsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $VisualStudio = & $VsWhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or -not $VisualStudio) { throw 'Visual Studio C++ tools are missing' }
    $Runtime = Get-ChildItem "$VisualStudio/VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT" -Directory |
        Sort-Object { [version]$_.Parent.Parent.Name } -Descending | Select-Object -First 1
    if (-not $Runtime) { throw 'Visual C++ runtime redistribution directory is missing' }
    foreach ($Name in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        Copy-Item (Join-Path $Runtime.FullName $Name) $Bundle
    }
    $WebViewInstaller = Join-Path $Temporary 'MicrosoftEdgeWebView2RuntimeInstallerX64.exe'
    Invoke-WebRequest 'https://go.microsoft.com/fwlink/p/?LinkId=2124701' -OutFile $WebViewInstaller
    $Signature = Get-AuthenticodeSignature $WebViewInstaller
    if ($Signature.Status -ne 'Valid' -or $Signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation,') {
        throw 'WebView2 installer does not have a valid Microsoft signature'
    }
    Copy-Item '../docs/INSTALL.md' (Join-Path $Bundle 'INSTALL.md')
    $Archive = Join-Path $Dist "papyrus-$Tag-windows-x64.zip"
    Compress-Archive -Path "$Bundle/*" -DestinationPath $Archive -Force
    $Compiler = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'
    if (-not (Test-Path $Compiler)) { throw 'Inno Setup 6 is required on the packaging runner' }
    & $Compiler "/DAppVersion=$Version" "/DBuildNumber=$BuildNumber" "/DReleaseTag=$Tag" "/DBundleDirectory=$Bundle" "/DOutputDirectory=$Dist" "/DWebViewInstaller=$WebViewInstaller" '../packaging/windows/papyrus.iss'
    if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed' }
} finally {
    Remove-Item -Recurse -Force $Temporary
}
