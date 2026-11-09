; Inno Setup script for a portable repo tool installation.
; This installer packages a minimal, private full CPython runtime for repo only and
; downloads the current `repo` bootstrap loader during installation, so it can be
; used from cmd.exe and Git Bash with no global Python installation required.

; Override via command line, e.g. ISCC /DAppVersion=1.2.3 ... (build.cmd/build.sh
; forward extra arguments to ISCC). Falls back to the default below if omitted.
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppPublisher "Robert Bosch GmbH"
#define AppName "Google's repo tool for Windows"

#if !FileExists(SourcePath + "..\runtime\python\python.exe")
  #error Run scripts\prepare_assets.ps1 before compiling.
#endif

[Setup]
; Keep the original default AppId so existing repo_is1 entries are detected.
AppId=repo
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
; The bundled Python runtime is AMD64; use 64-bit install paths/registry.
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
; Do not reuse the x86 directory from an older installation.
UsePreviousAppDir=no
DefaultDirName={pf}\repo
OutputDir={#SourcePath}\..\build
OutputBaseFilename=repo-installer-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
PrivilegesRequired=admin
DisableProgramGroupPage=yes

[Files]
Source: "..\scripts\get_installer_identity.ps1"; Flags: dontcopy
Source: "..\scripts\download_repo_bootstrap.ps1"; Flags: dontcopy
Source: "..\scripts\proxy_support.ps1"; Flags: dontcopy
; The bootstrap loader is not part of the installer; Setup downloads it.
Source: "{tmp}\repo-bootstrap"; DestDir: "{app}\runtime\repo"; DestName: "repo"; Flags: external ignoreversion
Source: "..\bin\repo.cmd"; DestDir: "{app}\bin"; Flags: ignoreversion
Source: "..\bin\repo"; DestDir: "{app}\bin"; Flags: ignoreversion
Source: "..\scripts\configure_repo_windows.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\scripts\SymlinkPrivilege.cs"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\runtime\python\*"; DestDir: "{app}\runtime\python"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; Leftovers of the old embeddable Python layout would override the standard search path.
Type: files; Name: "{app}\runtime\python\python*._pth"
Type: files; Name: "{app}\runtime\python\python*.zip"

[UninstallDelete]
; Bytecode caches written at run time (e.g. by an elevated console) are not tracked by Setup.
Type: filesandordirs; Name: "{app}\runtime\python"

[Registry]
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}\bin"; Flags: preservestringtype; Check: NeedsAddPath(ExpandConstant('{app}\bin'))

[Code]
const
  UninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\repo_is1';

var
  PreviousUninstallNeedsRestart: Boolean;
  StepPage: TOutputProgressWizardPage;
  UninstallSummary: String;
  InstallerUserSid: String;
  ProxyPage: TInputQueryWizardPage;
  NeedProxyCredentials: Boolean;
  ProxyUser: String;
  ProxyPassword: String;

function ResolveInstallerUser(): String;
var
  IdentityFile: String;
  IdentityData: AnsiString;
  ExitCode: Integer;
  I: Integer;
begin
  Result := '';
  if InstallerUserSid <> '' then Exit;
  IdentityFile := ExpandConstant('{tmp}\installer-user.sid');
  try
    ExtractTemporaryFile('get_installer_identity.ps1');
    DeleteFile(IdentityFile);
    { Inno retains the original user's token when it elevates via UAC.
      Do not use Exec here: that would identify the elevated administrator. }
    if not ExecAsOriginalUser(
      ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      ExpandConstant('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{tmp}\get_installer_identity.ps1" -OutputFile "') + IdentityFile + '"',
      '', SW_HIDE, ewWaitUntilTerminated, ExitCode) then
      Result := 'Could not identify the user who started setup: ' + SysErrorMessage(ExitCode)
    else if ExitCode <> 0 then
      Result := 'Installer user identification failed (exit code ' + IntToStr(ExitCode) + ').'
    else if not LoadStringFromFile(IdentityFile, IdentityData) then
      Result := 'Could not read the installer user identity.'
    if Result <> '' then Exit;

    InstallerUserSid := Trim(String(IdentityData));
    if Copy(InstallerUserSid, 1, 4) <> 'S-1-' then
      Result := 'Invalid installer user SID.';
    for I := 5 to Length(InstallerUserSid) do
      if Pos(Copy(InstallerUserSid, I, 1), '0123456789-') = 0 then
        Result := 'Invalid installer user SID.';
    if Result = '' then
      Log('Original installer user SID: ' + InstallerUserSid);
  except
    Result := 'Installer user identification failed: ' + GetExceptionMessage;
  end;
  DeleteFile(IdentityFile);
  if Result <> '' then InstallerUserSid := '';
end;

{ Returns 0 on success, 2 if the proxy requires credentials, otherwise 1.
  ErrorText describes a failure. }
function DownloadRepoBootstrap(var ErrorText: String): Integer;
var
  TargetFile: String;
  ErrorFile: String;
  CredentialFile: String;
  Parameters: String;
  ErrorData: AnsiString;
  ExitCode: Integer;
begin
  Result := 1;
  ErrorText := '';
  TargetFile := ExpandConstant('{tmp}\repo-bootstrap');
  ErrorFile := TargetFile + '.error';
  CredentialFile := TargetFile + '.credentials';
  DeleteFile(TargetFile);
  DeleteFile(ErrorFile);
  DeleteFile(CredentialFile);
  try
    ExtractTemporaryFile('proxy_support.ps1');
    ExtractTemporaryFile('download_repo_bootstrap.ps1');
    Parameters := ExpandConstant('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{tmp}\download_repo_bootstrap.ps1" -OutputFile "') + TargetFile + '"';
    if ProxyUser <> '' then
    begin
      { Read and deleted by the script at once; never put the password on the command line. }
      SaveStringToFile(CredentialFile, ProxyUser + #13#10 + ProxyPassword + #13#10, False);
      Parameters := Parameters + ' -CredentialFile "' + CredentialFile + '"';
    end;
    Log('Downloading the repo bootstrap loader to ' + TargetFile);
    { Original user: the user's proxy settings and credentials apply. }
    if not ExecAsOriginalUser(
      ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      Parameters, '', SW_HIDE, ewWaitUntilTerminated, ExitCode) then
      ErrorText := 'Could not start the repo bootstrap download: ' + SysErrorMessage(ExitCode)
    else if (ExitCode = 0) and FileExists(TargetFile) then
      Result := 0
    else
    begin
      if ExitCode = 2 then Result := 2;
      ErrorText := 'The repo bootstrap loader could not be downloaded.';
      if LoadStringFromFile(ErrorFile, ErrorData) then
        ErrorText := ErrorText + ' ' + Trim(String(ErrorData));
    end;
  except
    ErrorText := 'The repo bootstrap download failed: ' + GetExceptionMessage;
  end;
  DeleteFile(CredentialFile);
  if Result <> 0 then
    Log('ERROR (' + IntToStr(Result) + '): ' + ErrorText)
  else
    Log('repo bootstrap loader downloaded.');
end;

procedure InitializeWizard();
begin
  { Silent installations cannot ask: /ProxyUser= and /ProxyPassword= are the alternative. }
  ProxyUser := ExpandConstant('{param:ProxyUser|}');
  ProxyPassword := ExpandConstant('{param:ProxyPassword|}');
  ProxyPage := CreateInputQueryPage(wpSelectDir,
    'Proxy authentication',
    'Your proxy server requires a user name and password.',
    'Enter the credentials for the proxy (for example DOMAIN\user). They are only used for this download and are not stored.');
  ProxyPage.Add('User name:', False);
  ProxyPage.Add('Password:', True);
  StepPage := CreateOutputProgressPage(
    'Preparing installation',
    'Setup is preparing the installation of repo.');
end;

{ The download runs when leaving the directory page, so that a missing connection
  or proxy sign-in is dealt with before anything is installed. }
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = ProxyPage.ID) and not NeedProxyCredentials;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Code: Integer;
  ErrorText: String;
begin
  Result := True;
  if (CurPageID <> wpSelectDir) and (CurPageID <> ProxyPage.ID) then Exit;
  if FileExists(ExpandConstant('{tmp}\repo-bootstrap')) then Exit;
  if CurPageID = ProxyPage.ID then
  begin
    ProxyUser := Trim(ProxyPage.Values[0]);
    ProxyPassword := ProxyPage.Values[1];
  end;

  WizardForm.NextButton.Enabled := False;
  try
    Code := DownloadRepoBootstrap(ErrorText);
  finally
    WizardForm.NextButton.Enabled := True;
  end;

  NeedProxyCredentials := (Code = 2);
  if Code = 2 then
  begin
    { From the directory page the proxy page follows; on the proxy page itself stay. }
    if CurPageID = ProxyPage.ID then
    begin
      MsgBox(ErrorText + #13#10#13#10 + 'Please check the user name and password.', mbError, MB_OK);
      Result := False;
    end;
  end
  else if Code <> 0 then
  begin
    MsgBox(ErrorText + #13#10#13#10 + 'An Internet connection is required during installation.', mbError, MB_OK);
    Result := False;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  PowerShellPath: String;
  ExitCode: Integer;
  ErrorText: String;
  PreviousFsRedirection: Boolean;
begin
  if CurStep <> ssPostInstall then Exit;

  Log('Configuring Windows (Developer Mode, symlink privilege).');
  WizardForm.StatusLabel.Caption := 'Step 5/5: Configuring Windows (Developer Mode, symlink privilege)...';
  WizardForm.FilenameLabel.Caption := '';
  WizardForm.Refresh;

  { Inno Setup 5.5.1: use System32 with WOW64 redirection disabled
    only while launching native PowerShell. Restore the previous state. }
  PowerShellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');

  ErrorText := '';
  if IsWin64 then
    PreviousFsRedirection := EnableFsRedirection(False);
  try
    if not Exec(PowerShellPath,
      ExpandConstant('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{app}\scripts\configure_repo_windows.ps1" -InstallerUserSid "') + InstallerUserSid + '"',
      ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ExitCode) then
      ErrorText := 'Could not start Windows configuration: ' + SysErrorMessage(ExitCode)
    else if ExitCode <> 0 then
      ErrorText := 'Windows configuration failed (exit code ' + IntToStr(ExitCode) + ').';
  finally
    if IsWin64 then
      EnableFsRedirection(PreviousFsRedirection);
  end;

  if ErrorText <> '' then
  begin
    ErrorText := ErrorText + #13#10 +
      'Developer Mode or the symlink privilege may not be configured. See ' + ExpandConstant('{commonappdata}\repo-installer.log');
    Log('ERROR: ' + ErrorText);
    SuppressibleMsgBox(ErrorText, mbError, MB_OK, IDOK);
  end;
end;

function UninstallPrevious(RootKey: Integer): String;
var
  Uninstaller: String;
  ExitCode: Integer;
begin
  Result := '';
  if not RegKeyExists(RootKey, UninstallKey) then
    Exit;

  if not RegQueryStringValue(RootKey, UninstallKey, 'UninstallString', Uninstaller) then
  begin
    Result := 'Cannot find the uninstaller for the existing repo installation.';
    Exit;
  end;

  { Inno Setup stores a quoted executable path without arguments here. }
  Uninstaller := RemoveQuotes(Trim(Uninstaller));
  if not FileExists(Uninstaller) then
  begin
    Result := 'Previous repo uninstaller not found: ' + Uninstaller;
    Exit;
  end;

  Log('Uninstalling previous repo installation: ' + Uninstaller);
  if not Exec(Uninstaller, '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART',
    '', SW_HIDE, ewWaitUntilTerminated, ExitCode) then
  begin
    Result := 'Cannot start the previous repo uninstaller: ' + SysErrorMessage(ExitCode);
    Exit;
  end;

  if ExitCode = 3010 then
  begin
    PreviousUninstallNeedsRestart := True;
    Result := 'Previous repo uninstall requested a restart; deferred until after installation.';
    Exit;
  end;
  if ExitCode <> 0 then
  begin
    Result := 'Previous repo uninstall failed (exit code ' + IntToStr(ExitCode) + ').';
    Exit;
  end;
  if RegKeyExists(RootKey, UninstallKey) then
    Result := 'The previous repo installation is still registered.';
end;

procedure TryUninstallPrevious(RootKey: Integer);
var
  Warning: String;
begin
  try
    if not RegKeyExists(RootKey, UninstallKey) then
      Exit;

    StepPage.SetText('Step 3/5: Uninstalling the previous repo installation...',
      'Please wait. If removal fails, the new installation will continue anyway.');
    Warning := UninstallPrevious(RootKey);
  except
    Warning := 'Previous repo uninstall raised an exception: ' + GetExceptionMessage;
  end;

  if Warning <> '' then
  begin
    Log('WARNING: ' + Warning + ' Continuing with repo installation.');
    UninstallSummary := UninstallSummary + #13#10 + Warning +
      ' The new installation was continued.';
  end
  else
  begin
    Log('Previous repo installation successfully uninstalled.');
    UninstallSummary := UninstallSummary + #13#10 +
      'The previous repo installation was successfully uninstalled.';
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then
  begin
    { Offer a reboot, but do not select it on the user's behalf. }
    WizardForm.YesRadio.Checked := False;
    WizardForm.NoRadio.Checked := True;
  end;
  { Non-modal summary: failures never require confirmation to continue.
    Silent installations still receive all messages in the setup log. }
  if (CurPageID = wpFinished) and (UninstallSummary <> '') then
  begin
    WizardForm.FinishedLabel.Caption := WizardForm.FinishedLabel.Caption + #13#10 +
      UninstallSummary;
    UninstallSummary := '';
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  { Run only after Install was confirmed, before copying any new files.
    Uninstall is best effort: never return an error or request a pre-install
    restart. Check every registry view even if an earlier attempt failed. }
  { Identify the original user before uninstalling or modifying anything. }
  StepPage.SetProgress(0, 5);
  StepPage.SetText('Step 1/5: Identifying the installing user...', '');
  StepPage.Show;
  try
    Result := ResolveInstallerUser();
    { Download first: if it fails, nothing (including the old version) has been touched. }
    if Result = '' then
    begin
      StepPage.SetProgress(1, 5);
      if FileExists(ExpandConstant('{tmp}\repo-bootstrap')) then
        StepPage.SetText('Step 2/5: The repo bootstrap loader has been downloaded.', '')
      else
      begin
        { Silent installations skip the wizard pages and download here. }
        StepPage.SetText('Step 2/5: Downloading the current repo bootstrap loader...',
          'Source: storage.googleapis.com');
        if DownloadRepoBootstrap(Result) <> 0 then
          Result := Result + ' An Internet connection is required during installation;' +
            ' pass /ProxyUser= and /ProxyPassword= if the proxy requires authentication.' +
            ' Nothing was changed.';
      end;
    end;
    if Result = '' then
    begin
      StepPage.SetProgress(2, 5);
      TryUninstallPrevious(HKLM32);
      TryUninstallPrevious(HKCU32);
      if IsWin64 then
      begin
        TryUninstallPrevious(HKLM64);
        TryUninstallPrevious(HKCU64);
      end;
      StepPage.SetProgress(3, 5);
    end;
  finally
    StepPage.Hide;
  end;
end;

function NeedRestart(): Boolean;
begin
  { Show the native restart choice after every interactive installation.
    Do not trigger a silent reboot just for this optional recommendation. }
  Result := (not WizardSilent) or PreviousUninstallNeedsRestart;
end;

function NeedsAddPath(Param: string): boolean;
var
  OrigPath: string;
begin
  if not RegQueryStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', OrigPath)
  then begin
    Result := True;
    exit;
  end;
  Result := Pos(';' + Param + ';', ';' + OrigPath + ';') = 0;
end;
