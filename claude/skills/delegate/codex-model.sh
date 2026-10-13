#!/usr/bin/env bash
# Resolve a Codex model alias and reasoning effort to launch arguments, at
# delegation time, from Codex's own model catalogue. An alias is a model
# codename — the Codex analogue of Claude's "sonnet" — and always means the
# newest listed model of that name, so a new generation is picked up with no
# edit. No full slug is written here.
#
#   codex-model.sh <alias> <effort>
#     alias:  a codename (e.g. sol, terra, luna) | inherit
#     effort: low | medium | high | xhigh
#   codex-model.sh --is-expensive <alias-or-slug>
#
# stdout, one line each: the model slug (empty for inherit), then the effort
# actually used. The reason for any adjustment or failure goes to stderr.
# Exit: 0 resolved, 2 usage, 3 not resolvable — the caller degrades to inherit.
# --is-expensive exits 0 for an opt-in-only model, 1 otherwise; it needs no
# catalogue, so it cannot fail open.
#
# Naming. Only models with visibility "list" and a string slug count, and a
# trailing -YYYY-MM-DD is ignored. A slug's generation is everything through
# its first segment holding a digit ("gpt-N" in "gpt-N-name-mini"); its
# codename is the segment after that ("name"). A slug without a version
# segment has no codename.
#
# Resolution. Among listed models with the alias as codename, take the highest
# generation version; prefer the plain "<generation>-<alias>" over variants
# (-mini, -pro) and over dated snapshots, then the lowest priority. No listed
# model of that name exits 3.
#
# Opt-in only. STANDARD lists the codenames that run freely; every other one
# (astra, any codename Codex ships later, a slug without one) is opt-in, so a
# new flagship cannot slip through. A snapshot or variant of a standard name
# (name-mini, name-2031-01-01) counts as it.
#
# Effort. Clamped down to the highest level the model lists at or below the
# request, but never to low unless low was asked for; failing that, up to its
# lowest listed delegate level. A model that
# lists no levels gets the request unchanged. "ultra" enables automatic task
# delegation and is refused outright; "max" is outside the delegate vocabulary.
set -euo pipefail

STANDARD="luna terra sol"

usage() { echo "usage: $0 <codename>|inherit low|medium|high|xhigh | --is-expensive <alias-or-slug>" >&2; exit 2; }
[ $# -eq 2 ] || usage
alias=$1 effort=$2
case "$alias" in
  --is-expensive) [ -n "$effort" ] || usage ;;
  *[!a-z]*|'') usage ;;
  *) case "$effort" in low|medium|high|xhigh) ;; *)
       echo "effort must be low|medium|high|xhigh (got '${effort}'); ultra is forbidden" >&2; exit 2 ;;
     esac ;;
esac

# The codename rule needs no catalogue, so the gate never depends on one.
codename() {
  jq -rn --arg s "$1" '
    ($s | sub("-[0-9]{4}-[0-9]{2}-[0-9]{2}$"; "")) as $b
    | (($b | match("^[^0-9]*[0-9][^-]*") | .string) // null) as $g
    | if ($s | test("^[a-z]+$")) then $s
      elif $g == null or $b == $g then ""
      else ($b[($g | length) + 1:] | split("-")[0]) end'
}
if [ "$alias" = --is-expensive ]; then
  command -v jq >/dev/null || { echo "jq is not installed" >&2; exit 2; }
  c=$(codename "$effort")
  ! { [ -n "$c" ] && grep -qxF -- "$c" <(tr ' ' '\n' <<<"$STANDARD"); }; exit
fi

if [ "$alias" = inherit ]; then
  printf '\n%s\n' "$effort"
  exit 0
fi

command -v jq >/dev/null || { echo "jq is not installed; cannot read the codex model catalogue" >&2; exit 3; }
cache=${CODEX_MODELS_CACHE:-$HOME/.codex/models_cache.json}
[ -r "$cache" ] || { echo "codex model catalogue missing: $cache" >&2; exit 3; }

err=$(mktemp); trap 'rm -f "$err"' EXIT
resolved=$(jq -r --arg alias "$alias" '
  def base: sub("-[0-9]{4}-[0-9]{2}-[0-9]{2}$"; "");
  def gen: base | ((match("^[^0-9]*[0-9][^-]*") | .string) // null);
  def codename: base as $b | ($b | gen) as $g
    | if $g == null or $b == $g then null else ($b[($g | length) + 1:] | split("-")[0]) end;
  def version: gen | [scan("[0-9]+") | tonumber];
  if (.models | type) != "array" then error("no models array") else . end
  | [.models[] | select(type == "object" and .visibility == "list" and (.slug | type) == "string")] as $m
  | [$m[] | select((.slug | codename) == $alias)] as $c
      | if ($c | length) == 0 then empty else
          ($c | map(.slug | version) | max) as $v
          | [$c[] | select((.slug | version) == $v)]
          | sort_by((if (.slug | base) == ((.slug | gen) + "-" + $alias) then 0 else 1 end),
                    (if .slug == (.slug | base) then 0 else 1 end),
                    (.priority // 1e9), .slug)
          | .[0]
          | .slug,
            ([.supported_reasoning_levels[]? | if type == "object" then .effort else . end
              | strings] | if length == 0 then "-" else join(" ") end)
        end' "$cache" 2>"$err") || {
  echo "codex model catalogue unreadable: $cache ($(head -c 200 "$err"))" >&2; exit 3; }

slug=$(sed -n 1p <<<"$resolved")
levels=$(sed -n 2p <<<"$resolved")
[ -n "$slug" ] || { echo "no listed codex model is named $alias" >&2; exit 3; }

order=(low medium high xhigh)
used=
if [ "$levels" = - ]; then
  used=$effort
  echo "$slug lists no reasoning levels; passing effort $effort through" >&2
else
  # Highest supported level at or below the request, else lowest above it;
  # never down to low unless low was asked for (a lighter effort is the
  # caller's decision, not the clamp's). Exact tokens only: "extra-high" must
  # not count as "high".
  below=1
  for e in "${order[@]}"; do
    if { [ "$e" != low ] || [ "$effort" = low ]; } && tr ' ' '\n' <<<"$levels" | grep -qxF -- "$e"; then
      if [ "$below" = 1 ]; then used=$e
      elif [ -z "$used" ]; then used=$e; fi
    fi
    [ "$e" = "$effort" ] && below=0
  done
  [ -n "$used" ] || { echo "$slug lists none of the delegate efforts ($levels)" >&2; exit 3; }
  [ "$used" = "$effort" ] || echo "$slug does not support effort $effort; using $used" >&2
fi

printf '%s\n%s\n' "$slug" "$used"
