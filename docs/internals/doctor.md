# Doctor architecture

Moved verbatim from `CLAUDE.md` so the agent instructions stay short. `CLAUDE.md` keeps the rules that must hold on every edit; this file has the full module tree and naming rules.

```
doctor.sh                    # Entry point: sources lib + modules, guards the repo, exits 1 on ERROR
scripts/doctor/
├── lib.sh                   # group/ok/err/warn/note/summary, counters, doctor_q, doctor_assignment, doctor_require_repo
├── checks/                  # Run in this order by doctor.sh
│   ├── symlinks.sh          # check_symlinks   — from `git ls-files -s` mode 120000
│   ├── references.sh        # check_references — from Lua require(), Hyprlang source, literal paths
│   ├── binaries.sh          # check_binaries   — from Lua keybind/autostart hl.exec_cmd() calls
│   ├── services.sh          # check_services   — from autostart daemons, failed respawn.sh units, D-Bus roles, install.sh arrays
│   ├── sddm.sh              # check_sddm       — from sddm/setup-sudo.sh and the live SDDM configuration
│   ├── updates.sh           # check_updates    — from updates/setup-sudo.sh and sudo -l
│   ├── waybar.sh            # check_waybar     — from config.jsonc's modules-* arrays and handler values
│   ├── workspaces.sh        # check_workspaces — placed cffi/* modules: library present and current
│   ├── hyprctl.sh           # check_hyprctl    — removed runtime CLI forms under the Lua provider
│   ├── hardware.sh          # check_hardware   — /sys/class/drm present set vs tracked files
│   ├── autostart.sh         # check_autostart  — per-user XDG autostart entries whose program is missing
│   ├── ssh.sh               # check_ssh        — from hypr/config/setup/envvars.lua and scripts/ssh/setup.sh
│   ├── calendar.sh          # check_calendar   — from calendar-sync.timer, install.sh's calendar packages and the keyring
│   ├── defaults.sh          # check_defaults   — from envvars.lua's hl.env(apps.*) lines, options/, mimeapps.list
│   ├── state.sh             # check_state      — from defaults/ and the overlay's own check
│   ├── plugins.sh           # check_plugins    — gi:// imports' typelibs, defaults/qt*ct styles' Qt plugins
│   └── themes.sh            # check_themes     — selected GTK, icon, cursor and Kvantum themes that are not installed
└── test/
    ├── run-tests.sh         # Dependency-free harness; auto-discovers test-*.sh
    └── test-*.sh            # One per module, plus lib and entry point; sourced into one shell
```

All modules are sourced into a single shell, so: one public `check_<name>` function each, private helpers prefixed (`_ref_`, `_bin_`, `_svc_`, `_sddm_`, `_upd_`, `_way_`, `_wsm_`, `_hctl_`, `_hw_`, `_as_`, `_ssh_`, `_cal_`, `_def_`, `_st_`, `_plg_`, `_thm_`), and reserved names (`group ok err warn note summary doctor_reset doctor_q doctor_assignment doctor_require_repo _finding`) are never redefined. Host probes (`pgrep`, `pacman`, `busctl`, `command -v` via `_way_have_cmd`, `/sys/class/drm` via `_hw_present_outputs`, `$HOME` via `_wsm_home`, the build script's `--check` via `_wsm_current`, typelib and Qt style lookups via `_plg_typelib_present` and `_plg_qt_style_present`, theme lookups via `_thm_present`) each live in their own tiny function so tests can stub them — or aim them at a fixture, which is what `DOCTOR_DRM_SYSFS`, `DOCTOR_QT_LIBDIR` and `DOCTOR_THEME_HOME`/`DOCTOR_THEME_SHARE` do.

`ok` is the all-clear and nothing else — print it only when a check found nothing at all, never as a consolation summary. Every path in a fix hint goes through `doctor_q`, and hints never contain `<placeholder>` text (the shell parses `<foo>` as a redirection).
