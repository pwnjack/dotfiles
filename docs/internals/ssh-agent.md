# SSH agent

Moved verbatim from `CLAUDE.md` so the agent instructions stay short. `CLAUDE.md` keeps the rules that must hold on every edit; this file has the reasoning and the traps.

OpenSSH's packaged `ssh-agent.socket` (socket-activated, keys in memory only)
holds the key, so its passphrase is asked once per login. `SSH_AUTH_SOCK` is set
by `hypr/config/setup/envvars.lua` (`$XDG_RUNTIME_DIR/ssh-agent.socket`, guarded
against an unset runtime dir): Hyprland launches every app and terminal, so the
plain `Hyprland` session and the uwsm one both get it — `environment.d` would
reach only the latter. The line's `true` flag (`hl.env`'s `dbus` argument) also
exports it to the systemd user manager and the D-Bus activation environment each
session, which uwsm's fixed export list would not, so systemd units and
D-Bus-activated apps (Ghostty) see it. Already-open terminals get it at the next
login; `setup.sh`'s `set-environment` only covers the current session until then. The
tracked `ssh/config` holds only `AddKeysToAgent yes`.
`~/.ssh` is outside the repo, so `scripts/ssh/setup.sh` (run by `install.sh`
after the deploy step, no prompt) gives it a pointer: `Include ~/.config/ssh/config`
as the **first** line of `~/.ssh/config`, because a line after a `Host` or
`Match` block applies to that block alone. ssh uses the first value it reads, so
the tracked `AddKeysToAgent yes` takes precedence over one already in the user's
config (setup prints a notice; edit `ssh/config` to keep theirs). It backs the
file up to `<backup dir>/.ssh/config` first, as the deploy step does, and prints
the restore command. It never edits a symlinked `~/.ssh/config`: a symlink whose
target already has the Include is simply accepted, otherwise it is reported. A
symlink problem, an existing backup, or a failed enable skips only that step; the
rest still runs and setup exits 1. ssh refuses an Include target that is group or
world writable, so setup repairs the fragment with `chmod go-w` and doctor's
`check_ssh` warns when it finds it that way. `checks/ssh.sh` reads the unit name
and Include line from `setup.sh` and the socket name from the `envvars.lua` line
(both use the same sed).
