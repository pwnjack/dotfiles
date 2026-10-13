#!/usr/bin/env bash
# Wire the tracked AI-agent harness (claude/, codex/) into a machine.
#
# Only what this repo authored is linked or merged in; everything the agents or
# other tools write — logins, history, memory, caches, their own hooks — is left
# to them, so a fresh install stays fresh. Every step is optional: a missing
# claude, codex or herdr is skipped, never an error. Idempotent.
#
#   scripts/agents/setup.sh [--dry-run]
#
# Links: claude/skills/*/ -> ~/.claude/skills/, claude/hooks/*.sh (not their
# test-*.sh) -> ~/.claude/hooks/, claude/CLAUDE.global.md -> ~/.claude/CLAUDE.md,
# codex/AGENTS.global.md -> ~/.codex/AGENTS.md (CLAUDE_CONFIG_DIR and CODEX_HOME
# are honoured, as the apply scripts do). Anything already at a link target is
# moved — never deleted — into ~/.local/state/dotfiles-agents-backup/<time>/,
# outside the directories the agents scan, so an old skill cannot load twice.
# Links into this repo whose target is gone (a removed skill or hook) are
# deleted.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
dry=false
[ "${1:-}" = --dry-run ] && dry=true
claude_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
codex_dir=${CODEX_HOME:-$HOME/.codex}
backup_root="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-agents-backup/$(date +%Y%m%d-%H%M%S)"

run() { if $dry; then echo "  would run: $*"; else "$@"; fi; }
have() { command -v "$1" >/dev/null 2>&1; }

link() {
  local src=$1 dst=$2
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then return; fi
  run mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    local rel=${dst#"$HOME"/} n=1
    local bak="$backup_root/${rel#/}"
    while [ -e "$bak" ] || [ -L "$bak" ]; do bak="$backup_root/${rel#/}.$n"; n=$((n + 1)); done
    echo "  moving aside existing $dst -> $bak"
    run mkdir -p "$(dirname "$bak")"
    run mv "$dst" "$bak"
  fi
  run ln -s "$src" "$dst"
  $dry || echo "  linked $dst"
}

have jq || { echo "agents: jq is required; skipping harness setup" >&2; exit 1; }

if have claude; then
  echo "claude: linking harness"
  for d in "$repo"/claude/skills/*/; do
    d=${d%/}; link "$d" "$claude_dir/skills/$(basename "$d")"
  done
  for h in "$repo"/claude/hooks/*.sh; do
    case ${h##*/} in test-*) continue ;; esac
    link "$h" "$claude_dir/hooks/$(basename "$h")"
  done
  for l in "$claude_dir"/skills/* "$claude_dir"/hooks/*; do
    if [ -L "$l" ] && [ ! -e "$l" ] && [[ $(readlink "$l") == "$repo"/claude/* ]]; then
      echo "  removing stale link $l"; run rm "$l"
    fi
  done
  link "$repo/claude/CLAUDE.global.md" "$claude_dir/CLAUDE.md"
  run bash "$repo/claude/apply-settings.sh"

  # Plugins named in the tracked settings: add their marketplaces, then install.
  # Listing them initializes Claude's own state, so a dry run skips the query
  # and shows every step as it would run on a fresh machine.
  have_mkt=
  $dry || have_mkt=$(claude plugin marketplace list --json 2>/dev/null | jq -r '.[].name' || true)
  while IFS=$'\t' read -r name src; do
    grep -qxF -- "$name" <<<"$have_mkt" || run claude plugin marketplace add "$src"
  done < <(jq -r '.extraKnownMarketplaces | to_entries[]
                  | [.key, (.value.source | .repo // .url)] | @tsv' "$repo/claude/settings.json")
  have_plug=
  $dry || have_plug=$(claude plugin list --json 2>/dev/null | jq -r '.[].id' || true)
  while read -r plugin; do
    grep -qxF -- "$plugin" <<<"$have_plug" || run claude plugin install "$plugin" --scope user
  done < <(jq -r '.enabledPlugins | to_entries[] | select(.value) | .key' "$repo/claude/settings.json")
else
  echo "claude: not installed, skipping"
fi

if have codex; then
  echo "codex: linking harness"
  link "$repo/codex/AGENTS.global.md" "$codex_dir/AGENTS.md"
  run bash "$repo/codex/apply-config.sh"
else
  echo "codex: not installed, skipping"
fi

# Herdr owns its agent-state hooks and rewrites them on update, so they are
# installed through Herdr rather than tracked.
if have herdr; then
  for agent in claude codex; do
    have "$agent" || continue
    if ! $dry && herdr integration status 2>/dev/null | grep -q "^$agent: current"; then continue; fi
    run herdr integration install "$agent"
  done
fi
