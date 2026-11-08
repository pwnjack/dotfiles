# SDDM greeter wallpaper sync

`sddm/watch_wallpaper.sh` follows awww changes and asks `sddm/update_sddm.sh`
to refresh the greeter background. The passwordless-sudo target is a root-owned
copy installed under `/usr/local/bin`, while the tracked
`sddm/update_sddm_root.sh` remains its source and upgrade path. This separation
prevents the automatic NOPASSWD path from running a user-writable script as
root; the rule installed by setup pins the helper's sole argument to the
invoking username. The manual path remains privileged: `setup-sudo.sh` installs
from `$SCRIPT_DIR/update_sddm_root.sh` in the user's home, so anything able to
change that source gains root execution the next time setup is run. Re-run
setup only after reviewing source changes. The SDDM doctor check uses the
effective `sudo -l` grant, validates the installed helper and resolved theme
directory ownership, and detects stalled propagation. The helper remains
privileged only for its destination: wallpaper discovery and ffmpeg decoding
run as the target user, while root creates a temporary JPEG inside the theme's
`Backgrounds` directory and atomically renames it over the greeter background
after a successful decode, under one lock (`/run/lock/sddm-wallpaper.lock`)
held from wallpaper discovery to publication, so two helpers started by the
watcher cannot publish out of order. The resolved theme and `Backgrounds`
directories must remain root-owned and not writable by group or others, so an
unprivileged user cannot substitute either side of that privileged rename. The
doctor's `check_sddm` mirrors the helper's rules (the `[Theme]` `Current` grammar
and this ownership and mode test); a change to one lands in the other and in
`scripts/doctor/test/test-sddm.sh`, or the doctor reports healthy while every
sync fails.
