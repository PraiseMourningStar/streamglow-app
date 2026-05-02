#ifndef MyAppVersion
  #define MyAppVersion "dev"
#endif

#define MyAppName "StreamGlow"
#define MyAppPublisher "PraiseMourningStar"
#define MyAppURL "https://github.com/PraiseMourningStar/streamglow-app"
#define MyAppExeName "StreamGlow.exe"
#define MyRoot ".."

[Setup]
AppId={{1C52CC1B-8E5A-4815-8223-3E9A29F295EA}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={localappdata}\Programs\StreamGlow
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir={#MyRoot}\release
OutputBaseFilename=StreamGlow-Setup-{#MyAppVersion}
SetupIconFile={#MyRoot}\branding\windows\streamglow.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64compatible
LicenseFile={#MyRoot}\LICENSE

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "{#MyRoot}\dist\StreamGlow\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autodesktop}\StreamGlow"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{group}\StreamGlow"; Filename: "{app}\{#MyAppExeName}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch StreamGlow"; Flags: nowait postinstall skipifsilent
