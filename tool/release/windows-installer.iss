; Build with tool/release/windows.ps1. Install all runtime files, never user data.
#ifndef SourceDir
  #error SourceDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef AppIcon
  #error AppIcon is required
#endif

[Setup]
AppId={{4C508188-1247-4723-AD3A-360FDF6DCB58}
AppName=NexaPOS
AppVersion={#AppVersion}
AppPublisher=NexaPOS
DefaultDirName={localappdata}\Programs\NexaPOS
DefaultGroupName=NexaPOS
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=NexaPOS-Windows-Setup
SetupIconFile={#AppIcon}
UninstallDisplayIcon={app}\NexaPOS.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\NexaPOS"; Filename: "{app}\NexaPOS.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\NexaPOS"; Filename: "{app}\NexaPOS.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\NexaPOS.exe"; Description: "Open NexaPOS"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
