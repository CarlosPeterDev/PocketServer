; Inno Setup script for PocketServer (Windows). Build: iscc /DAppVersion=1.0.N tool\installer.iss
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{6D1B6E3A-5C0E-4B7B-9C6B-2F0B7A9E4C11}
AppName=PocketServer
AppVersion={#AppVersion}
AppPublisher=Carlos
DefaultDirName={autopf}\PocketServer
DefaultGroupName=PocketServer
DisableProgramGroupPage=yes
OutputDir=..\out
OutputBaseFilename=PocketServer-windows-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
PrivilegesRequired=admin
UninstallDisplayIcon={app}\pocketserver.exe
SetupIconFile=..\windows\runner\resources\app_icon.ico

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
Name: "firewall"; Description: "Allow PocketServer through Windows Firewall (needed so other devices can connect)"
Name: "autostart"; Description: "Start PocketServer when I sign in to Windows"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\PocketServer"; Filename: "{app}\pocketserver.exe"
Name: "{autodesktop}\PocketServer"; Filename: "{app}\pocketserver.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "PocketServer"; ValueData: """{app}\pocketserver.exe"""; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""PocketServer"" dir=in action=allow program=""{app}\pocketserver.exe"" enable=yes profile=private,domain"; Flags: runhidden; Tasks: firewall
Filename: "{app}\pocketserver.exe"; Description: "Launch PocketServer"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""PocketServer"""; Flags: runhidden
