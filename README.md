# repo Windows Installer

Self-contained repo launcher and private embedded Python for Windows x64.
Compiler: **Inno Setup 5.5.1**. Git for Windows must be installed separately.

## Directory layout

- `repo_installer.iss`: installer definition (project entry point).
- `build.cmd` / `build.sh`: build entry points for Windows CMD and Git Bash.
- `tools/InnoSetup5.5.1/`: bundled Inno Setup compiler (build only).
- `bin/repo.cmd`: Windows CMD launcher.
- `bin/repo`: Git Bash launcher.
- `runtime/repo/repo`: the **only** copy of the upstream repo bootstrap.
- `runtime/python/`: the **only** extracted embedded Python runtime.
- `scripts/prepare_assets.ps1`: prepare missing runtime assets on the build machine.
- `scripts/configure_repo_windows.ps1`: Windows configuration on the target machine.
- `build/`: generated installer output.

The two launchers address different shells; neither is generated or copied into
the project root. The source and installed runtime layouts are identical.

## Prepare assets (no system Python required)

From this directory in PowerShell, run `& ./scripts/prepare_assets.ps1`.
It downloads the repo bootstrap and Python 3.12.9 embeddable x64 package from
their official URLs only when the runtime is missing. The Python download is
extracted in a temporary staging directory and its ZIP is deleted afterwards.
No persistent download cache or duplicate runtime is kept.

For an offline completeness check use `& ./scripts/prepare_assets.ps1 -Offline`.
Preserve or transfer the complete `runtime/` directory for offline builds.
If the runtime is already present, preparation performs no downloads.

## Build and local use

From this directory, compile using `build.cmd` in Windows CMD,
`./build.cmd` in PowerShell, or `bash ./build.sh` in Git Bash.
Both scripts use the bundled `tools/InnoSetup5.5.1/ISCC.exe`, work when called
from another directory, and return the compiler's exit code. Optional compiler
switches are forwarded, e.g. `build.cmd /Q` or `bash ./build.sh /Q`.
Prepare the runtime assets first as described above; building does not download
anything or run the installer. No compiler installation or PATH change is needed.
Output: `build/repo-installer.exe`.

Run locally using `./bin/repo.cmd --help` (PowerShell/CMD) or
`./bin/repo --help` (Git Bash). Both use the private runtime directly; no Python
activation, system Python, or global Python PATH change is needed.

The installer packages `bin/`, `runtime/` and the Windows configuration script.
The asset-preparation script and the Python download ZIP are not installed.
Python's `python312.zip` **is required**: it is the standard library, not the
redundant download archive. Installation itself is offline; the repo bootstrap's
`repo init`/`repo sync` operations still need access to their Git repositories.

## Reinstallation

After confirming Install, setup looks for the existing `repo_is1` uninstall registration in HKLM/HKCU (32-bit and 64-bit views). It runs that installation's uninstaller silently and waits for completion before copying new files. Uninstall is best effort: missing uninstallers, nonzero exit codes, exceptions, or a remaining uninstall registration are logged as warnings and do not block the new installation. All registry views are checked even if an earlier attempt fails. A restart requested by the uninstaller (exit code 3010) is deferred until after installation.

A successful uninstall also removes the old installer-managed ZIP and nested bootstrap layout. Unregistered folders and user-created files are not recursively deleted. If uninstall fails, leftovers may remain; ordinary installation failures such as locked files, file/directory conflicts or insufficient permissions can still prevent copying new files. A failure after uninstall does not restore the previous installation. Use setup's `/LOG` option to capture uninstall warnings.

The new Python files are tracked by Inno Setup and removed during uninstall. Older releases extracted Python at installation time, so those old untracked files may remain; setup does not indiscriminately delete the installation directory.

The generated installer places the repo helper under `%ProgramFiles%\repo` and adds the `bin` folder to the user PATH so `repo` is directly callable from both `cmd.exe` and Git Bash.

## Windows settings applied by the installer

Setup requires administrator rights. The configuration script attempts to enable
Developer Mode in the native registry view (64-bit on Windows x64) and reads
back the DWORD value to verify the write. Setup launches native PowerShell and
shows a configuration error if the script fails; details are recorded in
`%ProgramData%\repo-installer.log`. A blocking Developer Mode policy is reported,
not overwritten. The registry check does not replace an actual symlink test.
The symlink-privilege step uses the Windows LSA API through
`scripts/SymlinkPrivilege.cs`; no external `ntrights.exe` is required. It adds
`SeCreateSymbolicLinkPrivilege` directly to **pol2hi** and reads the
assignment back. Existing accounts and their rights are preserved. Failures
are logged and shown by setup instead of being silently ignored.

In Local Security Policy > Local Policies > User Rights Assignment > Create
symbolic links, expect **pol2hi** (possibly displayed as `DOMAIN\pol2hi`).
The account is resolved to its SID and logged with its qualified name; an unknown
account fails visibly. The target is `$symlinkAccount` in the configuration
script; use a qualified `DOMAIN\pol2hi` or `COMPUTER\pol2hi` if account names
are ambiguous. Neither the Users group nor the UAC administrator is substituted.
Earlier group assignments are not automatically removed because setup cannot
distinguish pre-existing permissions from assignments made by older installers.
Sign out and
back in for a new access token. The assignment is retained on uninstall.
Domain policies may override the local assignment at the next refresh and must
be managed by the domain administrator. Open a new shell for PATH changes.
