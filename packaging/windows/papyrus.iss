[Setup]
AppId={{EE12464D-190B-4F05-B5D7-C333AE7DFA91}
AppName=Papyrus
AppVersion={#AppVersion}+{#BuildNumber}
VersionInfoVersion={#AppVersion}
AppVerName=Papyrus {#ReleaseTag}
AppPublisher=PapyrusReader
AppPublisherURL=https://papyrus-reader.com
DefaultDirName={localappdata}\Programs\Papyrus
DefaultGroupName=Papyrus
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDirectory}
OutputBaseFilename=papyrus-{#ReleaseTag}-windows-x64-setup
SetupIconFile=..\..\app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\papyrus.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Files]
Source: "{#BundleDirectory}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#WebViewInstaller}"; Flags: dontcopy

[Icons]
Name: "{group}\Papyrus"; Filename: "{app}\papyrus.exe"

[Run]
Filename: "{app}\papyrus.exe"; Description: "Open Papyrus"; Flags: nowait postinstall skipifsilent

[Code]
function HasWebViewRuntime: Boolean;
var
  Version: String;
  ClientKey: String;
begin
  ClientKey := 'Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';
  Result := (RegQueryStringValue(HKLM32, ClientKey, 'pv', Version) and
    (Version <> '') and (Version <> '0.0.0.0'));
  if not Result then
    Result := (RegQueryStringValue(HKCU, ClientKey, 'pv', Version) and
      (Version <> '') and (Version <> '0.0.0.0'));
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Result := '';
  if not HasWebViewRuntime then
  begin
    ExtractTemporaryFile('MicrosoftEdgeWebView2RuntimeInstallerX64.exe');
    if not Exec(ExpandConstant('{tmp}\MicrosoftEdgeWebView2RuntimeInstallerX64.exe'),
      '/silent /install', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
      Result := 'Could not start the bundled Microsoft WebView2 Runtime installer.'
    else if (ResultCode <> 0) and (ResultCode <> 3010) then
      Result := 'Microsoft WebView2 Runtime installation failed: ' + IntToStr(ResultCode)
    else if ResultCode = 3010 then
      NeedsRestart := True
    else if not HasWebViewRuntime then
      Result := 'Microsoft WebView2 Runtime was not detected after installation.';
  end;
end;
