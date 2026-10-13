-- Window rules

local apps = require("config.apptype")

-- The bar's 40px plus, when floating, its 8px gap from the screen edge, then
-- gaps_out (10) -- but only when the bar is on top. At the bottom a window
-- flush with the top edge needs gaps_out alone.
local below_bar = 10
if apps.barPosition ~= "bottom" then
    below_bar = 40 + (apps.barStyle == "docked" and 0 or 8) + 10
end

hl.window_rule({
    name = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name = "fix-xwayland-drags",
    match = {
        class = "^$",
        title = "^$",
        xwayland = true,
        float = true,
        fullscreen = false,
        pin = false,
    },
    no_focus = true,
})

-- Floating apps
hl.window_rule({ name = "float-pavucontrol", match = { class = "^(org.pulseaudio.pavucontrol)$" }, float = true })
hl.window_rule({ name = "float-blueman", match = { title = "^(blueman-manager)$" }, float = true })
hl.window_rule({ name = "float-network-editor", match = { class = "^(nm-connection-editor)$" }, float = true })
hl.window_rule({ name = "float-waypaper", match = { class = "^(waypaper)$" }, float = true })
hl.window_rule({ name = "resources", match = { class = "^(net.nokyan.Resources)$" }, float = true, size = "1150 600" })
-- Calculator (Super+K): a small centred popup over the current workspace, not
-- a tile. GNOME Calculator's class is the app id, not its "Calculator" title.
hl.window_rule({
    name = "float-calculator",
    match = { class = "^(org[.]gnome[.]Calculator)$" },
    float = true,
    size = "380 620",
    center = true,
})

-- GTK file pickers
hl.window_rule({
    name = "float-file-picker",
    match = { title = "^(Open Files|Open Folder|Select Image|Change Download Location|File Picker)$" },
    float = true,
})
hl.window_rule({ name = "float-portal-picker", match = { class = "^(xdg-desktop-portal-gtk)$" }, float = true })
hl.window_rule({ name = "float-strata-picker", match = { class = "^(io\\.github\\.lgse\\.Strata\\.FileChooser)$" }, float = true })

-- AI sidebar (Super+A). scripts/hyprland/launch-chatbox.sh starts it with this
-- class; matching the class rather than the title is what lets size and move
-- apply, because the window opens titled "Ghostty" and only later becomes
-- "aichat".
hl.window_rule({
    name = "ai-sidebar",
    match = { class = "^(aichat[.]sidebar)$" },
    float = true,
    workspace = "special:aichat",
    -- Expressions, not percentages: with size "800 95%" and move "100%-810 2.5%"
    -- the window opened at the default size, centred, with no config error.
    size = "800 monitor_h-20",
    move = "monitor_w-810 10",
    opacity = "0.95",
    dim_around = true,
})

-- Browser picture-in-picture
hl.window_rule({
    name = "picture-in-picture",
    match = { title = "^(Picture-in-Picture)$" },
    float = true,
    pin = true,
    -- Fixed size, flush top right: the browser's own size ran off-screen.
    -- Inset by gaps_out (10) from the right and by below_bar from the top,
    -- so it lines up with tiled windows wherever the bar is.
    -- Percentages ("69.5% 4%") were silently ignored; use expressions.
    size = "768 432",
    move = "monitor_w-778 " .. below_bar, -- 768 + 10; 0.56 has no window_w variable
})

-- Game window rules. See docs/gaming-wow.md before changing these.
hl.window_rule({
    name = "battlenet-launcher",
    match = { class = "(?i)^battle[.]net[.]exe$" },
    float = true,
    size = "1920 1080",
    center = true,
})
hl.window_rule({
    name = "battlenet-gamescope",
    -- Hyprland matches the whole title, including the initial "Battle.net Login".
    match = { class = "^(gamescope)$", title = "^Battle[.]net.*$" },
    float = true,
    size = "1920 1080",
    center = true,
})

local function game_rule(name, match)
    hl.window_rule({
        name = name,
        match = match,
        workspace = "5",
        fullscreen = true,
        immediate = true,
        no_blur = true,
        no_shadow = true,
        decorate = false,
        idle_inhibit = "fullscreen",
    })
end

game_rule("wow-classic", { class = "(?i)^WowClassic[.]exe$" })
game_rule("wow-gamescope", { class = "^(gamescope)$", title = "^World of Warcraft( [(]grabbed[)])?$" })

-- Layer rules
local function layer(name, namespace, effects)
    effects.name = name
    effects.match = { namespace = namespace }
    hl.layer_rule(effects)
end

layer("blur-waybar", "^(waybar)$", { blur = true, ignore_alpha = 0.5 })
layer("blur-swaync-control-center", "^(swaync-control-center)$", { blur = true, ignore_alpha = 0.1 })
layer("blur-swaync-notifications", "^(swaync-notification-window)$", { blur = true, ignore_alpha = 0.1 })
layer("blur-settings-panel", "^(settings-panel)$", { blur = true, ignore_alpha = 0.1 })
layer("blur-wallpaper-carousel", "^(wallpaper-carousel)$", { blur = true, ignore_alpha = 0.1, xray = false })
layer("blur-keybinds-overlay", "^(keybinds-overlay)$", { blur = true, ignore_alpha = 0.1, xray = false })
layer("blur-updates-popover", "^(updates-popover)$", { blur = true, ignore_alpha = 0.1, xray = false })
layer("blur-capture-bar", "^(capture-bar)$", { blur = true, ignore_alpha = 0.1, xray = false })
layer("blur-calendar-card", "^(calendar-card)$", { blur = true, ignore_alpha = 0.1, xray = false })
-- No close animation: the strip must be gone from the screen before its capture starts.
layer("noanim-capture-bar", "^(capture-bar)$", { no_anim = true })
