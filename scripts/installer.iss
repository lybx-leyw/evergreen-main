; Inno Setup script for Evergreen Multi-Tools
; Run after: flutter build windows --release
; Requires Inno Setup 6+: https://jrsoftware.org/isinfo.php

#define MyAppName "Evergreen Multi-Tools"
; Version can be overridden via command line: ISCC.exe /DMyAppVersion="1.2.0" installer.iss
#ifndef MyAppVersion
#define MyAppVersion "1.4.0"
#endif
#define MyAppPublisher "绿意不息"
#define MyAppURL "https://github.com/evergreen-multi-tools"
#define MyAppExeName "evergreen_multi_tools.exe"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=..\LICENSE
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
Source: "..\build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: ".env,.env.example,*.cookies,scripts\python\Lib\site-packages\onnx\backend\test\*,scripts\python\Lib\site-packages\onnxruntime\tools\*"
; Python OCR 脚本及依赖
Source: "..\scripts\*.py"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\scripts\requirements.txt"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\scripts\dist\*"; DestDir: "{app}\scripts\dist"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
; 嵌入式 Python 运行时（自带，无需用户安装 Python）
Source: "..\scripts\python\*"; DestDir: "{app}\scripts\python"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist; Excludes: "__pycache__\*,*.pyc,onnx\backend\test\*"
; zju-connect VPN 代理二进制（自带，无需用户下载）
Source: "..\vendor\zju-connect\*"; DestDir: "{app}\vendor\zju-connect"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
; pdf2zh 翻译引擎源码
Source: "..\scripts\pdf2zh_next\*"; DestDir: "{app}\scripts\pdf2zh_next"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
; 预置 Skill 文件
Source: "..\.greenix\skills\*"; DestDir: "{app}\.greenix\skills"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch Evergreen Multi-Tools"; Flags: nowait postinstall skipifsilent
