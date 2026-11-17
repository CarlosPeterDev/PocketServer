[Setup]
AppId=PocketServer
AppName=PocketServer
AppVersion=0.1.0
DefaultDirName={localappdata}\Programs\PocketServer
DefaultGroupName=PocketServer
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputBaseFilename=PocketServer-Setup-x64
Compression=lzma2
SolidCompression=yes

[Files]
Source: "{#AppSource}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\PocketServer"; Filename: "{app}\pocketserver_flutter.exe"
