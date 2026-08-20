; Kantin Otomasyonu — Inno Setup kurulum betigi
; ---------------------------------------------------------------------------
; docs/24 §5 · docs/31 Faz 12 · REQ-COMP-001/004 · BR-DATA-001
;
; MUTLAK KURAL — RSK-002'nin tek savunmasi:
;   Bu betik %APPDATA%\CanteenApp\ dizinine HICBIR SEKILDE DOKUNMAZ.
;   Ne kurulumda, ne guncellemede, ne de kaldirmada.
;   Kullanicinin veritabani, gorselleri, yedekleri ve oturumu oradadir;
;   installer oraya yazarsa bir guncelleme tum satis gecmisini silebilir.
;
; Betik Windows'ta Inno Setup 6.x ile derlenir:
;   1) flutter build windows --release
;   2) ISCC.exe installer\canteen.iss
; ---------------------------------------------------------------------------

#define AppName        "Kantin Otomasyonu"
#define AppVersion     "1.0.0"
#define AppPublisher   "Eygul Turizm"
#define AppExeName     "canteen.exe"
; flutter build windows --release ciktisi
#define BuildDir       "..\build\windows\x64\runner\Release"

[Setup]
AppId={{7F3C1D2E-9A54-4B6F-8E31-2C7A5D9E4B10}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
OutputDir=..\build\installer
OutputBaseFilename=KantinOtomasyonu-{#AppVersion}-kurulum
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

; docs/24 §5 — Windows 10 (1809+) ve Windows 11, yalnizca x64.
; 10.0.17763 = Windows 10 1809. Daha eskisinde kurulum baslamaz; yarim
; calisan bir kurulum, calismayan bir kurulumdan daha kotudur.
MinVersion=10.0.17763
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; Turkce arayuz varsayilandir (V1 tek dil).
ShowLanguageDialog=no

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "desktopicon"; Description: "Masaustu kisayolu olustur"; \
    GroupDescription: "Ek kisayollar:"

[Files]
; Uygulama dosyalari YALNIZCA {app} altina yazilir.
Source: "{#BuildDir}\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\*.dll";          DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\data\*";         DestDir: "{app}\data"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}";           Filename: "{app}\{#AppExeName}"
Name: "{group}\{#AppName} Kaldir";    Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}";     Filename: "{app}\{#AppExeName}"; \
    Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{#AppName} uygulamasini baslat"; \
    Flags: nowait postinstall skipifsilent

[UninstallDelete]
; YALNIZCA kurulum dizinindeki uygulama ciktilari silinir.
; {userappdata}\CanteenApp KASITLI OLARAK BURADA DEGILDIR (BR-DATA-001):
; kullanici uygulamayi kaldirip yeniden kursa bile verisi yerinde kalir.
Type: filesandordirs; Name: "{app}\data"

[Code]
{ Guncelleme (REQ-COMP-004): calisan surum acikken kurulum yapilirsa
  dosyalar kilitli olur ve kurulum yarim kalir. Windows'ta dosya kilitleme
  Unix'ten katidir (rules/05 §6), bu yuzden kullanici acikca uyarilir. }
function InitializeSetup(): Boolean;
var
  WindowHandle: HWND;
begin
  Result := True;
  WindowHandle := FindWindowByWindowName('{#AppName}');
  if WindowHandle <> 0 then
  begin
    MsgBox('{#AppName} su anda calisiyor.' + #13#10 + #13#10 +
           'Kuruluma devam etmeden once uygulamayi kapatin.' + #13#10 +
           'Verileriniz etkilenmeyecek.',
           mbError, MB_OK);
    Result := False;
  end;
end;
