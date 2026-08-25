#define MyAppName "Quantara"
#ifndef MyAppVersion
  #define MyAppVersion "1.2.0-rc.1"
#endif
#ifndef MyAppBuildRoot
  #define MyAppBuildRoot "..\..\src\client\quantara_app\build\windows\x64\runner\Release"
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

[Icons]
Name: "{autoprograms}\Quantara"; Filename: "{app}\quantara_app.exe"
Name: "{autodesktop}\Quantara"; Filename: "{app}\quantara_app.exe"; Tasks: desktopicon
Name: "{userstartup}\Quantara"; Filename: "{app}\quantara_app.exe"; Tasks: startup

[Run]
Filename: "{app}\quantara_app.exe"; Description: "Launch Quantara"; Flags: nowait postinstall skipifsilent

[Code]
function InitializeSetup(): Boolean;
begin
  Result := True;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  // No background execution worker is installed by the RC foundation.
  Result := '';
end;
