#!/usr/bin/env bash
# Type-check (luau-lsp, strict, Roblox API types), lint (selene) and test (lune).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
if [ ! -f build/globalTypes.d.luau ]; then
	curl -sSL -o build/globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions=@roblox=build/globalTypes.d.luau --definitions=@testez=scripts/testez.d.luau --sourcemap=sourcemap.json \
	--settings=.vscode/settings.json --no-strict-dm-types --base-luaurc=.luaurc src tests
# selene downloads the Roblox API dump on first run; skip (with a warning) when offline
if [ -f roblox.yml ] || selene generate-roblox-std >/dev/null 2>&1; then
	selene src tests
else
	echo "warning: selene skipped (could not fetch Roblox API dump)"
fi
lune run scripts/run-tests
