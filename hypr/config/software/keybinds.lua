-- This file is also the source of truth for the Super+H keybindings overlay and
-- docs/keybindings.md. Keep one hl.bind() per line and use a trailing `--`
-- comment as its human label.

local workspace_step = require("config.software.workspace_step")

return function(apps)
    -- ## Applications
    hl.bind("SUPER + RETURN", hl.dsp.exec_cmd(apps.terminal)) -- Terminal ($terminal)
    hl.bind("SUPER + E", hl.dsp.exec_cmd(apps.filemanager)) -- File manager ($filemanager)
    hl.bind("SUPER + N", hl.dsp.exec_cmd(apps.terminal .. " -e " .. apps.editor)) -- Text editor ($editor)
    hl.bind("SUPER + T", hl.dsp.exec_cmd("kwrite")) -- Text editor (KWrite)
    hl.bind("SUPER + B", hl.dsp.exec_cmd(apps.browser)) -- Web browser ($browser)
    hl.bind("SUPER + S", hl.dsp.exec_cmd("~/.config/scripts/hyprland/screenshot.sh region")) -- Screenshot a region
    hl.bind("SUPER + ALT + S", hl.dsp.exec_cmd("~/.config/scripts/hyprland/screenshot.sh region --annotate")) -- Screenshot a region and annotate
    hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("~/.config/scripts/hyprland/capture-bar.sh screenshot")) -- Capture bar: screenshot
    hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("~/.config/scripts/hyprland/capture-bar.sh record")) -- Capture bar: record, or stop
    hl.bind("SUPER + SHIFT + E", hl.dsp.exec_cmd("~/.config/scripts/hyprland/calendar-card.sh new")) -- New calendar event
    hl.bind("SUPER + G", hl.dsp.exec_cmd(apps.codeeditor)) -- Code editor ($codeeditor)
    hl.bind("SUPER + K", hl.dsp.exec_cmd("gnome-calculator")) -- Calculator
    hl.bind("SUPER + A", hl.dsp.exec_cmd("~/.config/scripts/hyprland/launch-chatbox.sh")) -- AI assistant sidebar

    -- ## Window Management
    hl.bind("SUPER + Q", hl.dsp.window.close()) -- Close window
    hl.bind("SUPER + W", hl.dsp.window.close()) -- Close window
    hl.bind("SUPER + SHIFT + Q", hl.dsp.exit()) -- Exit Hyprland
    hl.bind("ALT + F4", hl.dsp.window.close()) -- Close window
    hl.bind("SUPER + V", hl.dsp.window.float()) -- Toggle floating
    hl.bind("SUPER + F", hl.dsp.window.fullscreen()) -- Toggle fullscreen
    hl.bind("SUPER + SHIFT + F", hl.dsp.window.fullscreen({ mode = "maximized" })) -- Fullscreen without gaps
    hl.bind("SUPER + O", hl.dsp.layout("togglesplit")) -- Toggle split direction
    hl.bind("SUPER + P", hl.dsp.window.pseudo()) -- Toggle pseudo-tiling
    hl.bind("SUPER + SHIFT + V", hl.dsp.window.pin()) -- Pin window (always on top)
    hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/scripts/hyprland/lock.sh")) -- Lock screen

    -- ## Rofi Menus
    hl.bind("SUPER + SPACE", hl.dsp.exec_cmd("~/.config/rofi/launcher.sh")) -- App launcher
    hl.bind("SUPER + SHIFT + L", hl.dsp.exec_cmd("~/.config/rofi/powermenu.sh")) -- Power menu
    hl.bind("SUPER + C", hl.dsp.exec_cmd("~/.config/rofi/clipboard.sh")) -- Clipboard history
    hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("~/.config/scripts/hyprland/colorpicker.sh")) -- Colour picker (copies hex)
    hl.bind("SUPER + period", hl.dsp.exec_cmd("rofi -modi emoji -show emoji")) -- Emoji picker

    -- ## Notifications
    hl.bind("SUPER + SHIFT + N", hl.dsp.exec_cmd("swaync-client -t -sw")) -- Toggle notification sidebar

    -- ## Waybar
    hl.bind("SUPER + SHIFT + B", hl.dsp.exec_cmd("~/.config/scripts/waybar/waybar.sh")) -- Restart Waybar
    hl.bind("SUPER + ALT + B", hl.dsp.exec_cmd("~/.config/scripts/waybar/waybartoggle.sh")) -- Show/hide Waybar

    -- ## Settings & Utilities
    hl.bind("SUPER + I", hl.dsp.exec_cmd("$HOME/.config/scripts/hyprland/settings-panel.sh")) -- Settings panel
    hl.bind("SUPER + H", hl.dsp.exec_cmd("$HOME/.config/scripts/hyprland/keybinds-overlay.sh")) -- Keybindings
    hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd("waypaper --random")) -- Random wallpaper
    hl.bind("SUPER + CTRL + W", hl.dsp.exec_cmd("$HOME/.config/scripts/hyprland/wallpaper-carousel.sh")) -- Wallpaper carousel
    hl.bind("CTRL + SHIFT + ESCAPE", hl.dsp.exec_cmd("resources")) -- System monitor
    hl.bind("SUPER + SHIFT + D", hl.dsp.exec_cmd("~/.config/scripts/hyprland/nightlight.sh toggle")) -- Toggle night light
    hl.bind("SUPER + CTRL + D", hl.dsp.exec_cmd("~/.config/scripts/hyprland/nightlight.sh auto")) -- Night light: follow schedule

    -- ## Workspaces
    hl.bind("SUPER + 1", hl.dsp.focus({ workspace = 1 })) -- Switch to workspace
    hl.bind("SUPER + 2", hl.dsp.focus({ workspace = 2 })) -- Switch to workspace
    hl.bind("SUPER + 3", hl.dsp.focus({ workspace = 3 })) -- Switch to workspace
    hl.bind("SUPER + 4", hl.dsp.focus({ workspace = 4 })) -- Switch to workspace
    hl.bind("SUPER + 5", hl.dsp.focus({ workspace = 5 })) -- Switch to workspace
    hl.bind("SUPER + 6", hl.dsp.focus({ workspace = 6 })) -- Switch to workspace
    hl.bind("SUPER + 7", hl.dsp.focus({ workspace = 7 })) -- Switch to workspace
    hl.bind("SUPER + 8", hl.dsp.focus({ workspace = 8 })) -- Switch to workspace
    hl.bind("SUPER + 9", hl.dsp.focus({ workspace = 9 })) -- Switch to workspace
    hl.bind("SUPER + 0", hl.dsp.focus({ workspace = 10 })) -- Switch to workspace

    hl.bind("SUPER + SHIFT + 1", hl.dsp.window.move({ workspace = 1, follow = true })) -- Move window to workspace
    hl.bind("SUPER + SHIFT + 2", hl.dsp.window.move({ workspace = 2, follow = true })) -- Move window to workspace
    hl.bind("SUPER + SHIFT + 3", hl.dsp.window.move({ workspace = 3, follow = true })) -- Move window to workspace
    hl.bind("SUPER + SHIFT + 4", hl.dsp.window.move({ workspace = 4, follow = true })) -- Move window to workspace
    hl.bind("SUPER + SHIFT + 5", hl.dsp.window.move({ workspace = 5, follow = true })) -- Move window to workspace
    hl.bind("SUPER + SHIFT + 6", hl.dsp.window.move({ workspace = 6, follow = true })) -- Move window to workspace
    hl.bind("SUPER + SHIFT + 7", hl.dsp.window.move({ workspace = 7, follow = true })) -- Move window to workspace
    hl.bind("SUPER + SHIFT + 8", hl.dsp.window.move({ workspace = 8, follow = true })) -- Move window to workspace
    hl.bind("SUPER + SHIFT + 9", hl.dsp.window.move({ workspace = 9, follow = true })) -- Move window to workspace
    hl.bind("SUPER + SHIFT + 0", hl.dsp.window.move({ workspace = 10, follow = true })) -- Move window to workspace

    hl.bind("SUPER + CTRL + SHIFT + 1", hl.dsp.window.move({ workspace = 1, follow = false })) -- Move window, stay here
    hl.bind("SUPER + CTRL + SHIFT + 2", hl.dsp.window.move({ workspace = 2, follow = false })) -- Move window, stay here
    hl.bind("SUPER + CTRL + SHIFT + 3", hl.dsp.window.move({ workspace = 3, follow = false })) -- Move window, stay here
    hl.bind("SUPER + CTRL + SHIFT + 4", hl.dsp.window.move({ workspace = 4, follow = false })) -- Move window, stay here
    hl.bind("SUPER + CTRL + SHIFT + 5", hl.dsp.window.move({ workspace = 5, follow = false })) -- Move window, stay here
    hl.bind("SUPER + CTRL + SHIFT + 6", hl.dsp.window.move({ workspace = 6, follow = false })) -- Move window, stay here
    hl.bind("SUPER + CTRL + SHIFT + 7", hl.dsp.window.move({ workspace = 7, follow = false })) -- Move window, stay here
    hl.bind("SUPER + CTRL + SHIFT + 8", hl.dsp.window.move({ workspace = 8, follow = false })) -- Move window, stay here
    hl.bind("SUPER + CTRL + SHIFT + 9", hl.dsp.window.move({ workspace = 9, follow = false })) -- Move window, stay here
    hl.bind("SUPER + CTRL + SHIFT + 0", hl.dsp.window.move({ workspace = 10, follow = false })) -- Move window, stay here

    hl.bind("SUPER + CTRL + left", workspace_step.focus(-1)) -- Previous/next workspace
    hl.bind("SUPER + CTRL + right", workspace_step.focus(1)) -- Previous/next workspace
    hl.bind("SUPER + CTRL + SHIFT + left", workspace_step.move(-1)) -- Move window to prev/next
    hl.bind("SUPER + CTRL + SHIFT + right", workspace_step.move(1)) -- Move window to prev/next
    hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" })) -- Scroll through workspaces
    hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "e-1" })) -- Scroll through workspaces

    -- ## Window Focus & Movement
    -- Every navigation bind carries SUPER so Alt/Ctrl+arrows reach the app
    -- (browser back/forward, shell word jumps, editor line moves, TUIs).
    hl.bind("SUPER + left", hl.dsp.focus({ direction = "l" })) -- Move focus
    hl.bind("SUPER + right", hl.dsp.focus({ direction = "r" })) -- Move focus
    hl.bind("SUPER + up", hl.dsp.focus({ direction = "u" })) -- Move focus
    hl.bind("SUPER + down", hl.dsp.focus({ direction = "d" })) -- Move focus

    hl.bind("SUPER + TAB", hl.dsp.window.cycle_next({ next = true })) -- Cycle to next window
    hl.bind("SUPER + SHIFT + TAB", hl.dsp.window.cycle_next({ next = false })) -- Cycle to previous window

    hl.bind("SUPER + ALT + left", hl.dsp.window.resize({ x = -50, y = 0, relative = true }), { repeating = true }) -- Resize window
    hl.bind("SUPER + ALT + right", hl.dsp.window.resize({ x = 50, y = 0, relative = true }), { repeating = true }) -- Resize window
    hl.bind("SUPER + ALT + up", hl.dsp.window.resize({ x = 0, y = -50, relative = true }), { repeating = true }) -- Resize window
    hl.bind("SUPER + ALT + down", hl.dsp.window.resize({ x = 0, y = 50, relative = true }), { repeating = true }) -- Resize window

    hl.bind("SUPER + SHIFT + left", hl.dsp.window.move({ direction = "l" })) -- Move window
    hl.bind("SUPER + SHIFT + right", hl.dsp.window.move({ direction = "r" })) -- Move window
    hl.bind("SUPER + SHIFT + up", hl.dsp.window.move({ direction = "u" })) -- Move window
    hl.bind("SUPER + SHIFT + down", hl.dsp.window.move({ direction = "d" })) -- Move window

    -- ## Mouse Bindings
    hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true }) -- Move window (drag)
    hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true }) -- Resize window (drag)

    -- ## Media Keys
    hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 2%+"), { locked = true, repeating = true }) -- Volume up
    hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"), { locked = true, repeating = true }) -- Volume down
    hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true, repeating = true }) -- Mute output
    hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true, repeating = true }) -- Mute microphone
    hl.bind("XF86Calculator", hl.dsp.exec_cmd("gnome-calculator")) -- Calculator
    hl.bind("XF86AudioNext", hl.dsp.exec_cmd("~/.config/scripts/hyprland/mediactl.sh next"), { locked = true }) -- Next track
    hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("~/.config/scripts/hyprland/mediactl.sh play-pause"), { locked = true }) -- Play/pause
    hl.bind("XF86AudioPause", hl.dsp.exec_cmd("~/.config/scripts/hyprland/mediactl.sh play-pause"), { locked = true }) -- Play/pause
    hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("~/.config/scripts/hyprland/mediactl.sh previous"), { locked = true }) -- Previous track
end
