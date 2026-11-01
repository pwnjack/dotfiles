#!/bin/bash
# The keybinds' bounded previous/next workspace rule (workspace_step.lua),
# run under plain Lua: the pure step needs no Hyprland.
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
lua=$(command -v lua || command -v luajit) || { echo "skip: test-workspace-step (no lua)"; exit 0; }

LUA_PATH="$here/../?.lua;;" "$lua" - <<'LUA'
local step = require("config.software.workspace_step").step
local failed, checks = 0, 0
local function check(got, want, what)
    checks = checks + 1
    if got ~= want then
        failed = failed + 1
        print(("FAIL: %s (got %s, want %s)"):format(what, tostring(got), tostring(want)))
    end
end
local function with(...)
    local set = {}
    for _, id in ipairs({ ... }) do set[id] = true end
    return function(id) return set[id] == true end
end

local none = with()
check(step(1, none, 1), 2, "next from 1 goes to 2")
check(step(1, none, -1), nil, "previous from 1 stops at the first slot")
check(step(5, none, 1), nil, "next from 5 stops when 6-10 do not exist")
check(step(5, none, -1), 4, "previous from 5 goes to 4")
check(step(5, with(8), 1), 8, "next from 5 skips the hidden 6 and 7")
check(step(8, with(8), -1), 5, "previous from 8 skips back over 6 and 7")
check(step(8, with(8), 1), nil, "next from the last visible slot stops")
check(step(10, with(10), 1), nil, "next from 10 never leaves the row")
check(step(nil, with(10), 1), 1, "outside the row, next enters at the first slot")
check(step(12, with(10), -1), 10, "outside the row, previous enters at the last visible slot")
check(step(-98, with(8), -1), 8, "outside the row, previous skips hidden slots")
check(step(3, none, 0), nil, "no direction, no step")

print(("test-workspace-step: %d checks, %d failed"):format(checks, failed))
os.exit(failed == 0 and 0 or 1)
LUA
