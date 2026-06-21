; Inno Setup script for Voicely (Windows).
; Paths are relative to the windows/ folder (the CI runs ISCC from there).
; Installs per-user (no admin / UAC), with optional desktop + run-at-startup.

[Setup]
AppName=Voicely
AppVersion=0.1.0
AppPublisher=Gal Gershon
AppPublisherURL=https://voicely.app
AppSupportURL=https://github.com/Bactroban123/Voicely/issues
DefaultDirName={autopf}\Voicely
DefaultGroupName=Voicely
DisableProgramGroupPage=yes
OutputDir=installer_out
OutputBaseFilename=VoicelySetup
SetupIconFile=app\icon.ico
UninstallDisplayIcon={app}\Voicely.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64compatible
; Shown on the welcome page
AppComments=Press Ctrl+Alt+Space, speak, press again — text types itself.

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"
Name: "startup";     Description: "Start Voicely when Windows starts"; GroupDescription: "Startup:"

[Files]
Source: "dist\Voicely.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Voicely";         Filename: "{app}\Voicely.exe"
Name: "{autodesktop}\Voicely";   Filename: "{app}\Voicely.exe"; Tasks: desktopicon
Name: "{userstartup}\Voicely";   Filename: "{app}\Voicely.exe"; Tasks: startup

[Run]
Filename: "{app}\Voicely.exe"; \
  Description: "Launch Voicely now"; \
  Flags: nowait postinstall skipifsilent
