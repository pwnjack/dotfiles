# Hyprland dotfiles

A complete, ready-to-use Hyprland desktop for Arch Linux and CachyOS. Its
colours follow your wallpaper: change the wallpaper and the bar, launcher,
notifications, terminal, lock screen and apps all re-theme themselves.

![Arch](https://img.shields.io/badge/Arch_Linux-CachyOS-1793D1)
![Hyprland](https://img.shields.io/badge/Hyprland-0.55+-blue)
![License](https://img.shields.io/badge/License-GPL--3.0--or--later-blue)

## Install

On a fresh Arch Linux or CachyOS system, logged in as your normal user:

```bash
sudo pacman -S --needed git
git clone https://github.com/pwnjack/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

The installer asks before installing packages and backs up any file it
replaces; `./install.sh --dry-run` previews everything first. It also starts an
SSH agent, so your key's passphrase is asked once per login. CachyOS ships the
`paru` AUR helper it uses; on plain Arch, install `paru` or `yay` first.

When it finishes, log out and choose **Hyprland** at your login screen — or, if
you have no login manager, type `start-hyprland` in the console.

## What's inside

- **Colours that follow the wallpaper**: Hyprland, Hyprlock, Waybar, Rofi,
  notifications, Ghostty and its TUI apps (btop, cava, the Starship prompt),
  Neovim, Thunar, Discord (Vesktop), Zen Browser and Spotify all re-theme when
  the wallpaper changes, open windows included (Zen at its next launch). The
  login screen follows too.
- **Settings panel** for appearance, the bar, windows, animations,
  notifications, network, devices, displays, sound, power, keyboard and mouse,
  accessibility, date and region, startup apps and default apps, without
  editing config files.
- **Capture bar** for screenshots and screen recording, with annotation.
- **iCloud calendar** beside the clock, with the next event on the bar and a
  card to add, edit and delete events ([docs](docs/calendar.md)).
- **Wallpaper carousel**, a searchable **keybindings overlay**, and an
  **update card** that runs system updates from the bar.
- **Native workspace dots** on the bar, with smooth animation.
- **Night light** on a schedule, an **AI sidebar** (aichat), **virtual 7.1
  surround** for headphones, and a themed **Spotify** that SpotX keeps
  ad-free (when it is installed with spotify-launcher).
- **`./doctor.sh`** checks the live system against the config and tells you
  what is broken and how to fix it.

## First steps

| Keys | Does |
|---|---|
| `Super + Enter` | Terminal |
| `Super + Space` | App launcher |
| `Super + Ctrl + W` | Pick a wallpaper — colours follow |
| `Super + I` | Settings |
| `Super + H` | Every shortcut, searchable |

## Screenshots

Each wallpaper re-themes the whole desktop: bar, borders, terminal and overlays.

| | |
|---|---|
| ![Cosy retreat](screenshots/cosy-1.webp) | ![Cosy retreat, terminals](screenshots/cosy-2.webp) |
| ![Northern lights](screenshots/aurora-1.webp) | ![Northern lights, terminals](screenshots/aurora-2.webp) |
| ![Synthwave](screenshots/synthwave-1.webp) | ![Synthwave, terminals](screenshots/synthwave-2.webp) |

| Settings (`Super + I`) | Keybindings (`Super + H`) |
|---|---|
| ![Settings panel](screenshots/settings.webp) | ![Keybindings overlay](screenshots/keybinds.webp) |
| **Wallpaper carousel (`Super + Ctrl + W`)** | **Capture bar (`Super + Shift + S`)** |
| ![Wallpaper carousel](screenshots/carousel.webp) | ![Capture bar](screenshots/capture.webp) |

## More

- [Guide](docs/guide.md) — customisation, troubleshooting, maintenance, and
  links to a deep dive for each component
- [All keybindings](docs/keybindings.md)

## License

Copyright © 2026 pwnjack. Licensed under the GNU General Public License,
version 3 or any later version; see [LICENSE](LICENSE).
Vendored third-party files keep their own notices.
