#!/usr/bin/env bash
# Merge the tracked Claude Code settings (claude/settings.json) into
# ~/.claude/settings.json, leaving every other key in that file alone.
#
# The live file cannot be a tracked symlink: Claude Code, plugins and Herdr all
# write into it, often with absolute machine paths. So the tracked copy holds
# only the settings authored here and is merged in: objects merge key by key,
# and each tracked hook group is appended after removing, from the live groups,
# only the hooks that run the same script (matched by file name) — other hooks
# sharing a group survive, a group left empty is dropped, re-running never
# duplicates a hook, and a stale absolute-path copy of it is replaced. A live
# hook that runs a script under ~/.claude/hooks which no longer exists (one this
# repo used to ship) is dropped. Idempotent, and a no-op when Claude Code is not
# installed.
set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/settings.json"
target="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

command -v claude >/dev/null || [ -d "$(dirname "$target")" ] || { echo "claude: not installed, skipping"; exit 0; }
command -v jq >/dev/null || { echo "claude: jq is required to merge settings" >&2; exit 1; }
mkdir -p "$(dirname "$target")"
[ -s "$target" ] || echo '{}' > "$target"

tmp="$(mktemp "$target.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

# A fresh machine has no hooks directory yet: that is "no hooks", not an error.
present=$( { find "$(dirname "$target")/hooks" -maxdepth 1 -name '*.sh' -printf '%f\n' 2>/dev/null || true; } | jq -R . | jq -s .)

jq -s --argjson present "${present:-[]}" '
  def script: (.command // "") | (capture("(?<s>[^/\\s\"\\x{27}]+\\.sh)").s // .);
  .[0] as $live | .[1] as $mine
  | ($live * ($mine | del(.hooks)))
  | .hooks = (($live.hooks // {}) as $lh
      | reduce (($mine.hooks // {}) | to_entries[]) as $e ($lh;
          ([$e.value[].hooks[]? | script]) as $ours
          | .[$e.key] = ([(.[$e.key] // [])[]
                          | .hooks |= map(select(script as $s | ($ours | index([$s])) == null))
                          | select((.hooks | length) > 0)]
                         + $e.value)))
  | .hooks |= (with_entries(.value |= [.[]
        | .hooks |= map(select(((.command // "") | capture("\\.claude/hooks/(?<n>[^/\\s\"\\x{27}]+\\.sh)").n // null) as $n
                               | $n == null or ($present | index([$n])) != null))
        | select((.hooks | length) > 0)])
      | with_entries(select(.value | length > 0)))
' "$target" "$src" > "$tmp"

chmod --reference="$target" "$tmp" 2>/dev/null || true
if cmp -s "$tmp" "$target"; then
  echo "claude: settings already up to date"
else
  mv "$tmp" "$target"
  echo "claude: merged tracked settings into $target"
fi
