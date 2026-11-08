#!/bin/bash
# Wire the tracked SSH agent setup into this machine, so a key's passphrase is
# asked once per login: OpenSSH's socket-activated agent holds the key, and
# ssh/config (AddKeysToAgent yes) hands it over on first use. SSH_AUTH_SOCK
# is set by hypr/config/setup/envvars.lua, so every app and shell Hyprland
# launches inherits it, in the plain and the uwsm session alike.
#
#   scripts/ssh/setup.sh [--dry-run] [--backup-dir DIR | --no-backup]
#
# ~/.ssh lies outside this repo, so it only gets a pointer: an Include on the
# FIRST line of ~/.ssh/config. First, because ssh applies a line that follows a
# Host or Match block to that block alone. Before the file changes it is copied
# to <backup dir>/.ssh/config, as scripts/lib/deploy.sh does for every config it
# replaces; install.sh passes its own --backup-dir so one install makes one
# backup. A symlinked ~/.ssh/config belongs to someone else's dotfiles and is
# never edited. A problem there (symlink without the Include, backup already
# present) skips the config change, still runs the rest and exits 1 at the end.
# Idempotent and never interactive.
#
# Test seam: SSH_SETUP_REPO overrides the repo root (where
# hypr/config/setup/envvars.lua and ssh/ are read), so the tests can run against a private copy.
#
# checks/ssh.sh parses SSH_AGENT_UNIT and INCLUDE_LINE from this file, so keep
# each a single plain NAME="value" line. The socket name is read from the
# SSH_AUTH_SOCK line of envvars.lua; checks/ssh.sh parses it with the same sed.
set -euo pipefail

SSH_AGENT_UNIT="ssh-agent.socket"
# shellcheck disable=SC2088  # ssh expands the tilde itself
INCLUDE_LINE="Include ~/.config/ssh/config"

repo="${SSH_SETUP_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
dry=false
failed=0
backup="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) dry=true ;;
    --no-backup) backup="" ;;
    --backup-dir)
      if [ $# -lt 2 ] || [ -z "$2" ] || [[ $2 == -* ]]; then
        echo "ssh: --backup-dir needs a directory" >&2
        exit 2
      fi
      backup=$2
      shift
      ;;
    *) echo "ssh: unknown option '$1'" >&2; exit 2 ;;
  esac
  shift
done

run() { if $dry; then echo "  would run: $*"; else "$@"; fi; }
have_unit() {
  command -v systemctl >/dev/null 2>&1 \
    && systemctl --user cat "$SSH_AGENT_UNIT" >/dev/null 2>&1
}

# 1. The agent. Socket-activated: nothing runs until a client connects.
if have_unit; then
  if $dry; then echo "ssh: would enable $SSH_AGENT_UNIT"; else echo "ssh: enabling $SSH_AGENT_UNIT"; fi
  if ! run systemctl --user enable --now "$SSH_AGENT_UNIT"; then
    echo "ssh: could not enable $SSH_AGENT_UNIT; the Include is still set up" >&2
    failed=1
  fi
else
  echo "ssh: no $SSH_AGENT_UNIT user unit or no user session; skipping the agent"
fi

# 2. The Include, as the first line of ~/.ssh/config. ssh refuses an Include
# target that is group or world writable, which would break every ssh call.
fragment="$repo/ssh/config"
if [ -f "$fragment" ] && [ $((8#$(stat -c %a -- "$fragment") & 8#022)) -ne 0 ]; then
  echo "ssh: $fragment is group/world writable, which ssh refuses to include; running chmod go-w"
  run chmod go-w -- "$fragment"
fi

ssh_dir="$HOME/.ssh"
config="$ssh_dir/config"
first=""
if [ -f "$config" ]; then IFS= read -r first < "$config" || true; fi
# ssh ignores trailing whitespace, CR included, so the comparison does too.
first=${first%"${first##*[![:space:]]}"}

if [ "$first" = "$INCLUDE_LINE" ]; then
  echo "ssh: $config already includes the tracked fragment"
elif [ -L "$config" ]; then
  echo "ssh: $config is a symlink; left alone. Add this as the first line of its target:" >&2
  echo "  $INCLUDE_LINE" >&2
  failed=1
elif [ ! -e "$config" ]; then
  echo "ssh: creating $config"
  if $dry; then
    echo "  would create $config (mode 600) holding: $INCLUDE_LINE"
  else
    [ -d "$ssh_dir" ] || mkdir -m 700 -- "$ssh_dir"
    (umask 077 && printf '%s\n' "$INCLUDE_LINE" > "$config")
  fi
elif [ -n "$backup" ] && { [ -e "$backup/.ssh/config" ] || [ -L "$backup/.ssh/config" ]; }; then
  echo "ssh: $backup/.ssh/config already exists; not overwriting it, so $config is unchanged" >&2
  failed=1
else
  # Only a value other than yes conflicts with the tracked one.
  if grep -iE '^[[:space:]]*AddKeysToAgent([[:space:]]|=|$)' -- "$config" 2>/dev/null \
      | grep -qviE '^[[:space:]]*AddKeysToAgent[[:space:]]*[= ][[:space:]]*"?yes"?[[:space:]]*$'; then
    echo "ssh: $config sets AddKeysToAgent; the tracked 'AddKeysToAgent yes' now takes"
    echo "  precedence because ssh uses the first value it reads. To keep yours,"
    echo "  change $repo/ssh/config."
  fi
  if [ -n "$backup" ]; then
    echo "ssh: backing up $config to $backup/.ssh/config"
    run mkdir -p -- "$backup/.ssh"
    run cp -a -- "$config" "$backup/.ssh/config"
    if ! $dry; then
      printf 'ssh: to restore: cp -a %q %q\n' "$backup/.ssh/config" "$config"
    fi
  else
    echo "ssh: --no-backup given; not backing up $config"
  fi
  echo "ssh: adding '$INCLUDE_LINE' as the first line of $config"
  if $dry; then
    echo "  would rewrite $config with the Include first, contents and mode kept"
  else
    tmp=$(mktemp "$ssh_dir/.config.XXXXXX")
    trap 'rm -f -- "$tmp"' EXIT
    { printf '%s\n' "$INCLUDE_LINE"; cat -- "$config"; } > "$tmp"
    chmod --reference="$config" -- "$tmp"
    mv -f -- "$tmp" "$config"
    trap - EXIT
  fi
fi

# 3. The running user manager, so units started from now on see the socket.
# The name comes from the SSH_AUTH_SOCK line of envvars.lua (checks/ssh.sh
# parses the same line with the same sed).
envlua="$repo/hypr/config/setup/envvars.lua"
name=$(sed -n '/^[[:space:]]*--/b;/hl\.env("SSH_AUTH_SOCK"/{s/.*hl\.env("SSH_AUTH_SOCK", *runtime *\.\. *"\([^"]*\)" *\(, *true *\)\{0,1\}).*/\1/p;q;}' "$envlua" 2>/dev/null || true)
if [ -z "$name" ]; then
  echo "ssh: no SSH_AUTH_SOCK line in $envlua; skipping set-environment"
elif [ -n "${XDG_RUNTIME_DIR:-}" ] && have_unit; then
  run systemctl --user set-environment "SSH_AUTH_SOCK=$XDG_RUNTIME_DIR$name"
fi

# Terminals already open carry the old environment until the next login.
if $dry; then
  echo "ssh: dry run complete; nothing was changed"
else
  echo "ssh: done. Log out and back in so every terminal carries SSH_AUTH_SOCK."
fi
exit "$failed"
