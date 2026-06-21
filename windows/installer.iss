; Inno Setup script for "My Beautiful Wife".
; Paths are relative to the windows/ folder (the CI runs ISCC from there).
; Installs per-user (no admin / UAC), with optional desktop + run-at-startup.

[Setup]
AppName=My Beautiful Wife
AppVersion=1.0
AppPublisher=Gal
DefaultDirName={autopf}\My Beautiful Wife
DefaultGroupName=My Beautiful Wife
DisableProgramGroupPage=yes
OutputDir=installer_out
OutputBaseFilename=MyBeautifulWifeSetup
SetupIconFile=app\icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"
Name: "startup"; Description: "Start automatically when Windows starts"; GroupDescription: "Startup:"

[Files]
Source: "dist\MyBeautifulWife.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\My Beautiful Wife"; Filename: "{app}\MyBeautifulWife.exe"
Name: "{autodesktop}\My Beautiful Wife"; Filename: "{app}\MyBeautifulWife.exe"; Tasks: desktopicon
Name: "{userstartup}\My Beautiful Wife"; Filename: "{app}\MyBeautifulWife.exe"; Tasks: startup

[Run]
Filename: "{app}\MyBeautifulWife.exe"; Description: "Launch My Beautiful Wife now"; Flags: nowait postinstall skipifsilent
