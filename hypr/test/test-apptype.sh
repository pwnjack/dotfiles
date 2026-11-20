#!/bin/bash
# apptype.lua reads an option the way scripts/lib/options.sh does: trimmed, and
# a blank file means the fallback. Run under plain Lua with a fixture HOME.
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
lua=$(command -v lua || command -v luajit) || { echo "skip: test-apptype (no lua)"; exit 0; }
home=$(mktemp -d)
trap 'rm -rf "$home"' EXIT
mkdir -p "$home/.config/options"
printf 'firefox \r\n' > "$home/.config/options/browser"
printf '   \n' > "$home/.config/options/terminal"
printf 'kitty\n' > "$home/.config/options/editor"

HOME="$home" LUA_PATH="$here/../?.lua;;" "$lua" - <<'LUA'
local apps = require("config.apptype")
local failed = 0
local function check(got, want, what)
    if got ~= want then
        failed = failed + 1
        print(("FAIL: %s (got %q, want %q)"):format(what, got, want))
    end
end
check(apps.browser, "firefox", "padding and a CRLF are trimmed")
check(apps.terminal, "ghostty", "a whitespace-only file means the fallback")
check(apps.editor, "kitty", "a clean value is used as-is")
print(("test-apptype: %d failed"):format(failed))
os.exit(failed == 0 and 0 or 1)
LUA
