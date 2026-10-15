; Inno Setup script for the JoF Launcher Windows installer.
;
; Built by scripts/package-windows.ps1, which passes:
;   /DAppVersion=<x.y.z>   the launcher version, from pubspec.yaml
;   /DSourceDir=<dir>      the staged release bundle (exe, DLLs, data\)
;   /DOutputDir=<dir>      where jof-launcher-windows-setup.exe is written
;
; Installs per user into %LOCALAPPDATA%\Programs\JoF Launcher, so no admin
; prompt is needed and the install stays writable for in-app updates. The
; in-app updater runs this installer with
;   /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /relaunch=1
; which upgrades in place and starts the launcher again afterwards.

#ifndef AppVersion
  #error AppVersion must be defined, e.g. /DAppVersion=1.2.3
#endif
#ifndef SourceDir
  #error SourceDir must point at the staged release bundle
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif

#define AppName "JoF Launcher"
#define AppExeName "jof-launcher.exe"

[Setup]
; Never change AppId: it is how upgrades find the existing install.
AppId={{823D4CF5-F5D5-466E-B3FC-B1B30022852E}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=JoF
AppPublisherURL=https://github.com/JoFKypdurron/jof-launcher
AppSupportURL=https://github.com/JoFKypdurron/jof-launcher/issues
AppUpdatesURL=https://github.com/JoFKypdurron/jof-launcher/releases
VersionInfoVersion={#AppVersion}
PrivilegesRequired=lowest
DefaultDirName={autopf}\{#AppName}
DisableProgramGroupPage=yes
DefaultGroupName={#AppName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
OutputDir={#OutputDir}
OutputBaseFilename=jof-launcher-windows-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; The launcher must not be running while its files are replaced. The in-app
; updater exits before the installer gets here; this covers a manual upgrade.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; Flutter's assets are cleared before an upgrade so ones dropped from a
; release do not linger next to the new build.
Type: filesandordirs; Name: "{app}\data"

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
; In-app updates run silently and ask for the launcher to come back afterwards.
Filename: "{app}\{#AppExeName}"; Flags: nowait; Check: WizardSilent and RelaunchRequested

[Code]
function RelaunchRequested: Boolean;
begin
  Result := ExpandConstant('{param:relaunch|0}') = '1';
end;
