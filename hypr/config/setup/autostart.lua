return function(apps)
    hl.on("hyprland.start", function()
        -- System UI components. respawn.sh restarts a daemon that crashes
        -- and leaves one that was stopped on purpose alone.
        hl.exec_cmd("$HOME/.config/scripts/hyprland/respawn.sh waybar")
        hl.exec_cmd("$HOME/.config/scripts/hyprland/respawn.sh swaync")

        -- Wallpaper management
        hl.exec_cmd("awww-daemon")
        hl.exec_cmd("$HOME/.config/scripts/hyprland/restore-wallpaper.sh")
        hl.exec_cmd("$HOME/.config/sddm/watch_wallpaper.sh")

        -- System services
        hl.exec_cmd("$HOME/.config/scripts/hyprland/respawn.sh hypridle")
        hl.exec_cmd("$HOME/.config/scripts/hyprland/respawn.sh hyprsunset")
        hl.exec_cmd("systemctl --user start " .. apps.polkitAgent)
        hl.exec_cmd("wl-paste --type text --watch cliphist store")
        hl.exec_cmd("wl-paste --type image --watch cliphist store")

        -- User startup script
        hl.exec_cmd("$HOME/.config/scripts/hyprland/startup.sh")
    end)
end
