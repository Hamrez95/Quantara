#define MyAppName "Quantara"
#ifndef MyAppVersion
  #define MyAppVersion "1.2.0-rc.1"
#endif
#ifndef MyAppBuildRoot
  #define MyAppBuildRoot "..\..\src\client\quantara_app\build\windows\x64\runner\Release"
#endif
#ifndef MyServiceBuildRoot
  #define MyServiceBuildRoot "..\..\build\windows-service\Release"
#endif
#ifndef MyOutputDir
  #define MyOutputDir "..\..\dist\windows"
#endif

[Setup]
AppId={{F4173ECF-8DF4-4B5B-B51C-63F970D95590}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Quantara
DefaultDirName={autopf}\Quantara
DefaultGroupName=Quantara
DisableProgramGroupPage=yes
OutputDir={#MyOutputDir}
OutputBaseFilename=QuantaraSetup-{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayIcon={app}\quantara_app.exe
CloseApplications=yes
RestartApplications=no
VersionInfoProductName=Quantara
VersionInfoDescription=Quantara guarded trading cockpit

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked
Name: "startup"; Description: "Start Quantara with Windows (UI only, trading remains disarmed)"; GroupDescription: "Startup:"; Flags: unchecked

[Files]
Source: "{#MyAppBuildRoot}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#MyServiceBuildRoot}\quantara_windows_service.exe"; DestDir: "{app}\service"; Flags: ignoreversion
Source: "{#MyServiceBuildRoot}\quantara_windows_service_client.exe"; DestDir: "{app}\service"; Flags: ignoreversion
Source: "{#MyServiceBuildRoot}\quantara_windows_credentials.exe"; DestDir: "{app}\service"; Flags: ignoreversion
Source: "{#MyServiceBuildRoot}\quantara_windows_tray.exe"; DestDir: "{app}\service"; Flags: ignoreversion
Source: "..\..\scripts\manage-windows-service.ps1"; DestDir: "{app}\service"; Flags: ignoreversion
Source: "..\..\scripts\manage-windows-service.ps1"; Flags: dontcopy

[Icons]
Name: "{autoprograms}\Quantara"; Filename: "{app}\quantara_app.exe"
Name: "{autoprograms}\Quantara status monitor"; Filename: "{app}\service\quantara_windows_tray.exe"
Name: "{autodesktop}\Quantara"; Filename: "{app}\quantara_app.exe"; Tasks: desktopicon
Name: "{userstartup}\Quantara"; Filename: "{app}\quantara_app.exe"; Tasks: startup

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\service\manage-windows-service.ps1"" -Action Install -ServiceExe ""{app}\service\quantara_windows_service.exe"""; StatusMsg: "Registering Quantara service in a disarmed state..."; Flags: runhidden waituntilterminated
Filename: "{app}\quantara_app.exe"; Description: "Launch Quantara"; Flags: nowait postinstall skipifsilent
Filename: "{app}\service\quantara_windows_tray.exe"; Description: "Launch Quantara read-only status monitor"; Flags: nowait postinstall skipifsilent unchecked

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\service\manage-windows-service.ps1"" -Action Uninstall"; RunOnceId: "QuantaraExecutionServiceRemove"; Flags: runhidden waituntilterminated

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
  ScriptPath: String;
  Parameters: String;
begin
  // Stop an already-installed service before replacing its executable. The
  // helper treats a missing service as success and never starts/arms trading.
  ExtractTemporaryFile('manage-windows-service.ps1');
  ScriptPath := ExpandConstant('{tmp}\manage-windows-service.ps1');
  Parameters := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
    ScriptPath + '" -Action PrepareUpgrade';

  if not Exec(
    ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    Parameters,
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  ) then
  begin
    Result := 'Unable to prepare the Quantara background service for installation.';
    exit;
  end;

  if ResultCode <> 0 then
  begin
    Result := 'Quantara background service did not stop safely. Installation was cancelled.';
    exit;
  end;

  Result := '';
end;
