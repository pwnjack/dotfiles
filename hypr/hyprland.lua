--
-- HYPRLAND CONFIGURATION
-- Modern dark theme - matugen dynamic colours
--
-- Keeping the configuration split into modules contains errors: Hyprland
-- evaluates each require() in its own protected scope.
--

local apps = require("config.apptype")
local colors = require("config.colors")

require("config.hardware.monitor")
require("config.hardware.input")

require("config.setup.envvars")(apps)
require("config.setup.autostart")(apps)

require("config.looks.decor")(colors)
require("config.looks.animations")

require("config.software.general")
require("config.software.keybinds")(apps)
require("config.software.rules")

-- Settings changed in the Super+I panel (quickshell/settings-panel/persist.js)
-- live per machine in ${XDG_STATE_HOME:-~/.local/state}/hypr/overrides.lua, so
-- using the panel never dirties the repo. Loaded last so they win over the
-- tracked defaults; no file means none. A broken file is reported and skipped
-- rather than taking the rest of the config down.
local state_home = os.getenv("XDG_STATE_HOME")
if not state_home or state_home == "" then state_home = (os.getenv("HOME") or "") .. "/.local/state" end
local overrides = state_home .. "/hypr/overrides.lua"
-- The notification text is fixed: the Lua error comes from file content and
-- must never reach a shell.
local function overrides_failed(reason)
    print("overrides.lua: " .. tostring(reason))
    hl.exec_cmd("notify-send -u critical Settings 'Saved panel settings could not be fully applied; check overrides.lua'")
end
local file, open_err, errno = io.open(overrides, "r")
if file then
    file:close()
    local chunk, err = loadfile(overrides, "t")
    local ok = chunk ~= nil
    if ok then ok, err = pcall(chunk) end
    if not ok then overrides_failed(err) end
elseif errno ~= 2 then -- ENOENT: no file simply means no overrides.
    overrides_failed(open_err)
end
