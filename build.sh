
#!/usr/bin/env bash
set -euo pipefail

# Resolve all paths relative to this script, not the caller's directory.
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
compiler='./tools/InnoSetup5.5.1/ISCC.exe'
if [[ ! -f "$compiler" ]]; then
    printf 'ERROR: Missing %s.\n' "$compiler" >&2
    exit 1
fi

# Keep Inno switches such as /Q and /DName=value intact in Git Bash.
export MSYS2_ARG_CONV_EXCL='*'
exec "$compiler" "$@" 'repo_installer.iss'