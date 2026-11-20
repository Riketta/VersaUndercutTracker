#!/usr/bin/env bash
# Local CI parity: the gates that run without native rocks (Windows host):
#   stylua --check .            tools/stylua (scripts/bootstrap-tools.sh)
#   unit tests                  lua + scripts/run_tests.lua (busted shim)
#   TOC coverage                lua scripts/check_toc.lua
#   lua-language-server         tools/lls at --checklevel=Warning
# luacheck + real busted run in CI (GitHub Actions) via luarocks.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== stylua"
tools/stylua/stylua.exe --check .

echo "== unit tests (busted shim)"
lua scripts/run_tests.lua spec/*.lua

echo "== TOC coverage"
(
    cd VersaUndercutTracker
    lua ../scripts/check_toc.lua VersaUndercutTracker.toc .
    cd ../VUTProbe
    lua ../scripts/check_toc.lua VUTProbe.toc .
)

echo "== lua-language-server (Warning level)"
rm -f lls.log
tools/lls/bin/lua-language-server.exe --check=./ --checklevel=Warning > ./lls.log 2>&1 || true
lua scripts/assert_lls_clean.lua ./lls.log

echo "local gates ok (luacheck + real busted: see CI)"
