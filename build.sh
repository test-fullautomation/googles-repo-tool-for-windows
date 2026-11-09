
#!/usr/bin/env bash
set -euo pipefail

# Resolve all paths relative to this script, not the caller's directory.
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
compiler='./tools/InnoSetup5.5.1/ISCC.exe'
if [[ ! -f "$compiler" ]]; then
    printf 'ERROR: Missing %s.\n' "$compiler" >&2
    exit 1
fi

# Default: delete and download the runtime (Python) again.
# --keep-runtime (not passed to ISCC): keep existing runtime data, download only what is missing.
keep=()
iscc_args=()
for arg in "$@"; do
    if [[ "$arg" == '--keep-runtime' ]]; then keep=(-Keep); else iscc_args+=("$arg"); fi
done

if command -v powershell.exe >/dev/null 2>&1; then
    ps='powershell.exe'
elif command -v pwsh >/dev/null 2>&1; then
    ps='pwsh'
else
    printf 'ERROR: PowerShell (powershell.exe or pwsh) is required to prepare the runtime.\n' >&2
    exit 1
fi
"$ps" -NoProfile -ExecutionPolicy Bypass -File scripts/prepare_assets.ps1 ${keep[@]+"${keep[@]}"}

# Keep Inno switches such as /Q and /DName=value intact in Git Bash.
export MSYS2_ARG_CONV_EXCL='*'
exec "$compiler" ${iscc_args[@]+"${iscc_args[@]}"} 'installer/repo_installer.iss'