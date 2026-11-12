# Wallpaper carousel

`quickshell/wallpaper-carousel/shell.qml` is a separate on-demand Quickshell
application, opened by `scripts/hyprland/wallpaper-carousel.sh` (Super+Ctrl+W);
it exits on close and has no login autostart. Controls, integration, limits
and checks: [wallpaper-carousel.md](../wallpaper-carousel.md#integration).

- `carousel-apply.sh` is the apply path: it runs `wall.sh` synchronously exactly once, behind a nonblocking submission lock separate from `wall.sh`'s theme lock. Waypaper's own random selection and the SDDM wallpaper watcher are unaffected by it. [Integration](../wallpaper-carousel.md#integration).
- Waypaper cannot persist percent signs, and the query/INI boundary cannot represent line breaks; the helper rejects those names before submission. [Limits](../wallpaper-carousel.md#limits).
- The backdrop follows the shared blur settings in `decor.lua`. [Controls](../wallpaper-carousel.md#controls).
