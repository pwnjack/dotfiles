# SDDM greeter wallpaper sync

`sddm/watch_wallpaper.sh` follows awww changes and asks `sddm/update_sddm.sh` to
refresh the greeter background. The passwordless-sudo target is a root-owned
copy of `sddm/update_sddm_root.sh` in `/usr/local/bin`, never a user-writable
script; never point a sudo rule at one, and review the source before re-running
setup. The sudo rule pins the sole argument to the invoking username, and the
decode-as-user, temporary-file and atomic-rename flow is in
[sddm/README.md](../../sddm/README.md#setup).

- The helper holds one lock (`/run/lock/sddm-wallpaper.lock`) from wallpaper discovery to publication, so two helpers started by the watcher cannot publish out of order.
- The resolved theme and `Backgrounds` directories must be root-owned and not writable by group or others, so an unprivileged user cannot substitute either side of the rename (the README states only the root-owned half).
- The doctor's `check_sddm` mirrors the helper's rules (the `[Theme]` `Current` grammar and this ownership and mode test), using the effective `sudo -l` grant; a change to one lands in the other and in `scripts/doctor/test/test-sddm.sh` (the doctor) and `sddm/test-sddm.sh` (the scripts), or the doctor reports healthy while every sync fails.
