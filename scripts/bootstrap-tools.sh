#!/usr/bin/env bash
# One-time bootstrap for the gitignored local toolchain (Windows host):
#   StyLua 2.6.0               -> tools/stylua/stylua.exe
#   lua-language-server 3.19.1 -> tools/lls/bin/lua-language-server.exe
# Downloaded from official GitHub releases, verified against pinned sha256.
set -euo pipefail
cd "$(dirname "$0")/.."

STYLUA_VERSION=2.6.0
STYLUA_URL="https://github.com/JohnnyMorganz/StyLua/releases/download/v${STYLUA_VERSION}/stylua-windows-x86_64.zip"
STYLUA_SHA256=fd13b4014e3b779c244bbc03f2c282e357f15bc526de6a6fa5ecbc447538313c

LLS_VERSION=3.19.1
LLS_URL="https://github.com/LuaLS/lua-language-server/releases/download/${LLS_VERSION}/lua-language-server-${LLS_VERSION}-win32-x64.zip"
LLS_SHA256=fdb9a59108cf62517813c97fa5594b0e16d1ef0688306bac728b08434db7e4cd

command -v curl >/dev/null 2>&1 || {
    echo "error: curl is required (bundled with Git for Windows)" >&2
    exit 2
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d ' ' -f1
    else
        certutil -hashfile "$(cygpath -w "$1")" SHA256 | sed -n 2p | tr -d ' \r'
    fi
}

unzip_into() {
    if command -v unzip >/dev/null 2>&1; then
        unzip -o -q "$1" -d "$2"
    else
        powershell.exe -NoProfile -Command "\$d='$2' -replace '/', '\\'; Expand-Archive -Force -Path '$1' -DestinationPath \$d"
    fi
}

fetch_and_check() {
    echo "[bootstrap-tools] downloading $(basename "$3") ..."
    curl -fL --retry 3 -o "$3" "$1"
    local actual
    actual=$(sha256_of "$3")
    if [ "$(printf %s "$actual" | tr 'A-Z' 'a-z')" != "$(printf %s "$2" | tr 'A-Z' 'a-z')" ]; then
        echo "error: checksum mismatch for $3" >&2
        exit 1
    fi
}

mkdir -p tools/stylua tools/lls

if tools/stylua/stylua.exe --version 2>/dev/null | grep -q "$STYLUA_VERSION"; then
    echo "[bootstrap-tools] stylua $STYLUA_VERSION already present"
else
    tmp=$(mktemp -d)
    fetch_and_check "$STYLUA_URL" "$STYLUA_SHA256" "$tmp/stylua.zip"
    unzip_into "$tmp/stylua.zip" tools/stylua
    rm -rf "$tmp"
    tools/stylua/stylua.exe --version
fi

if tools/lls/bin/lua-language-server.exe --version 2>/dev/null | grep -q "$LLS_VERSION"; then
    echo "[bootstrap-tools] lua-language-server $LLS_VERSION already present"
else
    tmp=$(mktemp -d)
    fetch_and_check "$LLS_URL" "$LLS_SHA256" "$tmp/lls.zip"
    unzip_into "$tmp/lls.zip" tools/lls
    rm -rf "$tmp"
    tools/lls/bin/lua-language-server.exe --version
fi

echo "[bootstrap-tools] done. Local gate: bash scripts/ci_local.sh"
