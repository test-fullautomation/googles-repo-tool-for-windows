; Inno Setup script for a portable repo tool installation.
; This installer packages the `repo` bootstrap script plus a minimal embedded
; Python runtime for repo only, so it can be used from cmd.exe and Git Bash
; with no global Python installation required.

#define AppVersion "0.9.1"
#define AppPublisher "Robert Bosch GmbH"
#define AppName "Google's repo tool for Windows"
#define RootDir "."

#if !FileExists(SourcePath + "runtime\python\python.exe")
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
OutputDir={#RootDir}\build
OutputBaseFilename=repo-installer
Compression=lzma2/max
SolidCompression=yes
PrivilegesRequired=admin
DisableProgramGroupPage=yes

[Files]
Source: "{#RootDir}\scripts\get_installer_identity.ps1"; Flags: dontcopy
Source: "{#RootDir}\runtime\repo\repo"; DestDir: "{app}\runtime\repo"; Flags: ignoreversion
Source: "{#RootDir}\runtime\repo\LICENSE"; DestDir: "{app}\runtime\repo"; Flags: ignoreversion
Source: "{#RootDir}\runtime\repo\THIRD-PARTY-NOTICES.txt"; DestDir: "{app}\runtime\repo"; Flags: ignoreversion
Source: "{#RootDir}\bin\repo.cmd"; DestDir: "{app}\bin"; Flags: ignoreversion
Source: "{#RootDir}\bin\repo"; DestDir: "{app}\bin"; Flags: ignoreversion
Source: "{#RootDir}\scripts\configure_repo_windows.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "{#RootDir}\scripts\SymlinkPrivilege.cs"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "{#RootDir}\runtime\python\*"; DestDir: "{app}\runtime\python"; Excludes: "__pycache__\*,*.pyc"; Flags: ignoreversion recursesubdirs createallsubdirs

[Registry]
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}\bin"; Flags: preservestringtype; Check: NeedsAddPath(ExpandConstant('{app}\bin'))

[Code]
const
  UninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\repo_is1';

var
  PreviousUninstallNeedsRestart: Boolean;
  UninstallProgressPage: TOutputProgressWizardPage;
  UninstallSummary: String;
  InstallerUserSid: String;

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

procedure InitializeWizard();
begin
  UninstallProgressPage := CreateOutputProgressPage(
    'Previous repo installation',
    'Removing the previous version before installing repo.');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  PowerShellPath: String;
  ExitCode: Integer;
  ErrorText: String;
  PreviousFsRedirection: Boolean;
begin
  if CurStep <> ssPostInstall then Exit;

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

    UninstallProgressPage.SetText('Uninstalling the previous repo installation...',
      'Please wait. If removal fails, the new installation will continue anyway.');
    UninstallProgressPage.SetProgress(0, 1);
    UninstallProgressPage.Show;
    try
      Warning := UninstallPrevious(RootKey);
      UninstallProgressPage.SetProgress(1, 1);
    finally
      UninstallProgressPage.Hide;
    end;
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
  Result := ResolveInstallerUser();
  if Result <> '' then Exit;
  TryUninstallPrevious(HKLM32);
  TryUninstallPrevious(HKCU32);
  if IsWin64 then
  begin
    TryUninstallPrevious(HKLM64);
    TryUninstallPrevious(HKCU64);
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
