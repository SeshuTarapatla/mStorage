; mStorage Inno Setup Script
; Prerequisites: Inno Setup 6+ (https://jrsoftware.org/isinfo.php)
;
; Build the installer:
;   iscc installer.iss
;
; Output: installer\mStorage_Setup.exe

#define AppName        "mStorage"
#define AppVersion     "1.0.0"
#define AppPublisher   "Seshu Tarapatla"
#define AppURL         "https://github.com/SeshuTarapatla/mStorage"
#define AppExeName     "m_storage.exe"
#define BuildDir       "build\windows\x64\runner\Release"

[Setup]
; Unique ID — keeps uninstall/upgrade working across versions. Do not change.
AppId={{F4A9D2E7-3B8C-4F6A-9D1E-7C2B5A8F3E4D}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
AllowNoIcons=yes
; Output
OutputDir=installer
OutputBaseFilename=mStorage_Setup_v{#AppVersion}
; Icon
SetupIconFile=windows\runner\resources\app_icon.ico
; Compression
Compression=lzma2/ultra64
SolidCompression=yes
; UI
WizardStyle=modern
; Require Windows 10 or later (Flutter Windows minimum)
MinVersion=10.0
; Install to Program Files, requires UAC — app appears in Apps & features for all users
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Include the entire Release folder (exe, DLLs, data/, assets)
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}";                          Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}";    Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}";                    Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
