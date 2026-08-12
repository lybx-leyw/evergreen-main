; Inno Setup — Evergreen
; 用法: flutter build windows (--release|--debug) 之后运行 ISCC.exe scripts\installer.iss
; 双版 × 双模式（CI 传参区分，见 .github/workflows/release.yml）：
;   浙大专用版: /DMyAppSuffix=-Zju  通用版: /DMyAppSuffix=-Std
;   模式:       /DMyBuildMode=Release | /DMyBuildMode=Debug
; 产物命名: EvergreenSetup{Zju|Std}-{Release|Debug}-<ver>.exe
; 打包内容: {Release|Debug} 构建产物（含 data/flutter_assets 的插件/脚本资产）
;           + .greenix/python（嵌入 Python，CI 预置到 build/greenix_dist/python）

#ifndef MyAppName
#define MyAppName "Evergreen"
#endif
#ifndef MyAppVersion
#define MyAppVersion "2.0.0"
#endif
#ifndef MyAppSuffix
#define MyAppSuffix ""
#endif
#ifndef MyBuildMode
#define MyBuildMode "Release"
#endif
#define MyAppPublisher "Evergreen"
#define MyAppExeName "evergreen_base.exe"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\build\installer
OutputBaseFilename=EvergreenSetup{#MyAppSuffix}-{#MyBuildMode}-{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
; Flutter {#MyBuildMode} 构建产物（exe + dll + data/，data/flutter_assets 含插件与脚本资产，
; App 启动时释放到 .greenix/plugins 与 .greenix/scripts）
Source: "..\build\windows\x64\runner\{#MyBuildMode}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\{#MyBuildMode}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; 嵌入式 Python 运行时（CI 预置：官方 embeddable + pip 依赖装好后放到
; build\greenix_dist\python）。App 运行时从 .greenix\python 解析（greenixPythonDir）。
Source: "..\build\greenix_dist\python\*"; DestDir: "{app}\.greenix\python"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
