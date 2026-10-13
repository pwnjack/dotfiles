-- Default applications and preferences used by keybinds, autostart and envvars.

local home = os.getenv("HOME") or ""

local function read_option(name, fallback)
    local file = io.open(home .. "/.config/options/" .. name, "r")
    if not file then
        return fallback
    end

    local value = file:read("*l")
    file:close()
    if not value or value == "" then
        return fallback
    end
    return value
end

return {
    browser = read_option("browser", "firefox"),
    terminal = read_option("terminal", "ghostty"),
    editor = read_option("editor", "nvim"), -- TUI editor, opened in the terminal
    codeeditor = read_option("codeeditor", "zeditor"), -- GUI code editor
    cursorTheme = read_option("cursortheme", "Bibata-Modern-Classic"),
    filemanager = read_option("filemanager", "strata"), -- GUI file manager (yazi for CLI)

    -- Where Waybar sits (the settings panel's Bar page); rules.lua keeps
    -- floating windows clear of it. Both rows reload Hyprland when saved.
    barPosition = read_option("bar-position", "top"),
    barStyle = read_option("bar-style", "floating"),

    -- The package ships this systemd user unit rather than a PATH executable.
    polkitAgent = "hyprpolkitagent.service",
}
