; Inno Setup — Evergreen Multi-Tools
; 用法: flutter build windows --release 之后运行 ISCC.exe scripts\installer.iss

#define MyAppName "Evergreen Multi-Tools"
#ifndef MyAppVersion
#define MyAppVersion "0.0.0"
#endif
#define MyAppPublisher "Evergreen"
#define MyAppExeName "evergreen_multi_tools.exe"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\build\installer
OutputBaseFilename=EvergreenSetup-{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
; Flutter 构建产物
Source: "..\build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: ".env,.env.example,*.cookies"

; Python OCR 脚本
Source: "..\scripts\*.py"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\scripts\requirements.txt"; DestDir: "{app}\scripts"; Flags: ignoreversion

; 嵌入式 Python 运行时
Source: "..\scripts\python\*"; DestDir: "{app}\scripts\python"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Dirs]
; 插件目录——安装后为空占位，用户放入插件即可热加载
Name: "{app}\plugins"
