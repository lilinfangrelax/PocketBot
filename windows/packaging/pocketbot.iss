; PocketBot Windows installer. Built by windows/packaging/package.ps1.
; The in-app updater downloads this Setup.exe. An installed copy exits, then runs:
;   Setup.exe /VERYSILENT /NORESTART /CURRENTUSER /DIR={app}
; [Run] uses skipifsilent, so this script does not launch PocketBot; the updater does.
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build-output"
#endif
#ifndef OutputDir
  #define OutputDir "..\.."
#endif
#ifndef SetupBaseName
  #define SetupBaseName "PocketBot-Windows-Setup"
#endif

[Setup]
AppId={{8F4C1A2E-6B7D-4E91-9C3A-1D5E7F0A2B64}
AppName=PocketBot
AppVersion={#AppVersion}
AppPublisher=PocketBot
DefaultDirName={localappdata}\PocketBot
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename={#SetupBaseName}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=lowest
UsePreviousAppDir=yes
WizardStyle=modern
UninstallDisplayIcon={app}\PocketBot.exe
CloseApplications=yes

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\PocketBot"; Filename: "{app}\PocketBot.exe"
Name: "{autodesktop}\PocketBot"; Filename: "{app}\PocketBot.exe"

[Run]
Filename: "{app}\PocketBot.exe"; Description: "Launch PocketBot"; Flags: nowait postinstall skipifsilent
