#!/usr/bin/env bash
# Run one worker, Codex or Claude, in a visible Herdr pane: spawn it beside the
# orchestrator, hand it a brief, wait until it needs the orchestrator, print a
# verdict. Run it with the Bash tool's run_in_background; the harness re-invokes
# the orchestrator when it exits.
#
#   pane.sh codex <alias> <effort> <slug> <brief-file>
#   pane.sh claude <alias> <effort> <slug> <brief-file>
#   pane.sh --wait <pane> <report> [minutes]   # resume after answering it
#
# Claude alias: a Claude Code model alias (haiku, sonnet, opus, ...). Codex
# alias: a codename (luna, terra, sol, ...) or inherit. Effort, both kinds:
# low|medium|high|xhigh. Only the standard names (CLAUDE_STANDARD here,
# STANDARD in codex-model.sh) run freely; any other, including one config.toml
# would launch, needs DELEGATE_EXPENSIVE=1, set only when the user asked. Slug:
# a-z0-9-, short enough that dlg-<kind>-<slug> fits Herdr's 32 characters.
#
# First stdout line: <VERDICT> pane=... report=... elapsed=...
#   REPORT 0  report written; pane closed      BLOCKED 3  approval or question
#   NOREPORT 4  worked, wrote no report        QUOTA 5  usage limit; pane closed
#   GONE 6  pane vanished   NOSTART 7  prompt never landed, or a start gate
#   NOHERDR 8  no pane made  TIMEOUT 124      usage errors exit 2, no verdict
# The pane stays open on BLOCKED, NOREPORT, NOSTART and TIMEOUT: read it,
# answer or re-prompt with `herdr agent prompt`, then run --wait, and close it
# with `herdr pane close` when done with it. DELEGATE_KEEP=1 keeps it open on
# REPORT too, for a fix round that resumes it; QUOTA still closes it.
#
# Workers start with Superpowers off: a leaf that brainstorms waits for an
# approval no one gives, and its session text would fill every worker.
set -uo pipefail

here=$(dirname "$(readlink -f "$0")")
poll=${DELEGATE_POLL:-3} quiet=${DELEGATE_QUIET:-20} land=${DELEGATE_LAND:-45}
start=$(date +%s) kind='' pane='' report='' model='' effort='' msg='' waiting='' landed=0

CLAUDE_STANDARD="haiku sonnet opus"
CLAUDE_PLUGINS_OFF='{"enabledPlugins":{"superpowers@anthropic-plugin-directory":false}}'
CODEX_PLUGINS_OFF='plugins."superpowers@openai-curated-remote".enabled=false'

usage() { echo "usage: $0 claude|codex <alias> <effort> <slug> <brief> | --wait <pane> <report> [minutes]" >&2; exit 2; }
screen() { herdr agent read "$pane" --source visible --format text 2>/dev/null | tail -n "${1:-40}"; }
status() { herdr agent get "$pane" 2>/dev/null | jq -r '.result.agent.agent_status // "gone"' 2>/dev/null || echo gone; }
# Checked only once the worker is idle, on the bottom of the screen, for the
# tools' own error wording: a task that merely mentions limits must not trip it.
quota() { screen 15 | grep -qiE "hit your usage limit|(usage|rate) limit (reached|exceeded)|not supported when using codex"; }
finish() { # verdict exit-code [close]
  echo "$1 pane=$pane report=$report${model:+ model=$model}${effort:+ effort=$effort} elapsed=$(( $(date +%s) - start ))s"
  if [ "$1" = REPORT ]; then
    jq '{status, summary, files_changed, blockers, concerns}' "$report" 2>/dev/null || cat "$report"
  else
    echo "--- screen ---"; screen 40
  fi
  [ "${3:-}" = close ] && herdr pane close "$pane" >/dev/null 2>&1
  exit "$2"
}

if [ "${1:-}" = --wait ]; then
  [ $# -ge 3 ] || usage
  pane=$2 report=$3 limit=$(( ${4:-45} * 60 )) waiting=1 landed=1
else
  kind=${1:-} limit=$(( 45 * 60 ))
  case "$kind" in claude|codex) ;; *) usage ;; esac
  [ $# -eq 5 ] || usage
  alias=$2 effort=$3 slug=$4 brief=$5
  case "$effort" in low|medium|high|xhigh) ;; *)
    echo "effort must be low|medium|high|xhigh (got '$effort')" >&2; exit 2 ;;
  esac
  case "$alias" in *[!a-z]*|'') usage ;; esac
  # Herdr agent names (dlg-<kind>-<slug>) max out at 32 characters.
  name=dlg-$kind-$slug
  case "$slug" in *[!a-z0-9-]*|'') usage ;; esac
  [ "${#name}" -le 32 ] || { echo "slug too long: $name is over 32 characters" >&2; exit 2; }
  [ -r "$brief" ] || { echo "brief not readable: $brief" >&2; exit 2; }
fi

# Gate opt-in models before touching Herdr, so a refused launch leaves no pane.
if [ "$kind" = claude ]; then
  grep -qxF -- "$alias" <(tr ' ' '\n' <<<"$CLAUDE_STANDARD") || [ "${DELEGATE_EXPENSIVE:-}" = 1 ] || {
    echo "claude $alias runs only on the user's explicit request (DELEGATE_EXPENSIVE=1)" >&2; exit 2; }
  model=$alias
  args=(--model "$alias" --effort "$effort" --append-system-prompt
        'You are a leaf worker. Do not delegate, spawn subagents, or start other agents. Do the work yourself.'
        --settings "$CLAUDE_PLUGINS_OFF")
elif [ "$kind" = codex ]; then
  rc=0; resolved=$("$here/codex-model.sh" "$alias" "$effort") || rc=$?
  case "$rc" in
    0) ;;
    3) echo "codex alias $alias unresolved; degrading to inherit" >&2
       resolved=$("$here/codex-model.sh" inherit "$effort") ;;
    *) exit 2 ;;
  esac
  model=$(sed -n 1p <<<"$resolved") effort=$(sed -n 2p <<<"$resolved")
  # inherit and the degrade path run config.toml's model (a profile wins), so
  # gate that too, and pin it with -m so the gated model is the one that runs.
  # A model that cannot be determined is refused.
  launched=$model
  if [ -z "$launched" ]; then
    launched=$(python3 -c '
import sys, tomllib
with open(sys.argv[1], "rb") as f: c = tomllib.load(f)
p = c.get("profile")
m = (c.get("profiles", {}).get(p, {}).get("model") if p else None) or c.get("model") or ""
print(m if isinstance(m, str) else "")' "${CODEX_CONFIG:-${CODEX_HOME:-$HOME/.codex}/config.toml}" 2>/dev/null || true)
    [ -n "$launched" ] || [ "${DELEGATE_EXPENSIVE:-}" = 1 ] || {
      echo "codex $alias would run config.toml's model, which cannot be determined; name an alias" >&2; exit 2; }
  fi
  for probe in "$alias" ${launched:+"$launched"}; do
    [ "$probe" != inherit ] || continue
    # Only a positive "standard" (exit 1) runs freely; a classifier error does not.
    rc=0; "$here/codex-model.sh" --is-expensive "$probe" 2>/dev/null || rc=$?
    if [ "$rc" != 1 ] && [ "${DELEGATE_EXPENSIVE:-}" != 1 ]; then
      echo "codex $probe runs only on the user's explicit request (DELEGATE_EXPENSIVE=1)" >&2; exit 2
    fi
  done
  model=${model:-$launched}
  args=(-c "$CODEX_PLUGINS_OFF" -c "model_reasoning_effort=$effort")
  [ -z "$model" ] || args=(-m "$model" "${args[@]}")
fi

if [ -n "$kind" ]; then
  # NOHERDR means outside Herdr, the only case where a caller may fall back to
  # an invisible worker; a broken Herdr inside a Herdr session is NOSTART.
  if [ "${HERDR_ENV:-}" != 1 ]; then
    echo "NOHERDR pane= report= model=$model effort=$effort elapsed=0s"; exit 8
  fi
  if ! command -v herdr >/dev/null || [ -z "${HERDR_PANE_ID:-}" ]; then
    echo "NOSTART pane= report= model=$model effort=$effort elapsed=0s"
    echo "inside Herdr, but the herdr command or HERDR_PANE_ID is missing"; exit 7
  fi
  dir=${DELEGATE_HANDOFF_DIR:-/tmp/delegate}; mkdir -p "$dir"
  report=$dir/$slug-$(date +%s).json

  # The orchestrator gets at most one delegate column: the first delegate splits
  # it right, later ones split the newest delegate down.
  column=$(herdr agent list | jq -r --arg tab "${HERDR_TAB_ID:-}" \
    '[.result.agents[] | select(.tab_id == $tab and ((.name // "") | startswith("dlg-")))] | last | .pane_id // empty')
  if [ -n "$column" ]; then split=(--pane "$column" --direction down)
  else split=(--pane "$HERDR_PANE_ID" --direction right); fi
  pane=$(herdr pane split "${split[@]}" --ratio 0.5 --no-focus \
    | jq -r '.result.pane_id // .result.pane.pane_id // empty')
  [ -n "$pane" ] || { echo "NOSTART pane= report=$report elapsed=0s"; echo "pane split failed"; exit 7; }
  herdr agent start "$name" --kind "$kind" --pane "$pane" --timeout 60000 -- "${args[@]}" >/dev/null \
    || finish NOSTART 7 close
  if screen | grep -qiE 'do you trust|trust this (folder|directory)|sign in|log ?in to|press enter to continue'; then
    finish NOSTART 7
  fi

  msg="Read the brief at $brief and follow it exactly. Finally, even if you failed, write your report to $report as JSON with exactly these keys: status (complete|partial|failed), summary, files_changed, commands_run, tests_run, blockers, concerns."
  herdr agent prompt "$pane" "$msg" >/dev/null
fi

resent=0 quiet_since=
while :; do
  now=$(date +%s); el=$(( now - start ))
  [ "$el" -lt "$limit" ] || finish TIMEOUT 124
  # Codex can open a hook-review screen that swallows the first prompt while
  # Herdr reports working, possibly after the first poll: escape, resend once.
  if [ -z "$waiting" ] && [ "$el" -lt "$land" ] && screen | grep -qE 'Hooks +— +[0-9]+ hooks? needs? review'; then
    [ "$resent" = 0 ] || finish NOSTART 7
    herdr agent send-keys "$pane" esc >/dev/null; sleep 1
    herdr agent prompt "$pane" "$msg" >/dev/null; resent=1 landed=0
    sleep "$poll"; continue
  fi
  st=$(status)
  if [ "$st" != working ] && jq -e . "$report" >/dev/null 2>&1; then
    [ "${DELEGATE_KEEP:-}" = 1 ] && finish REPORT 0; finish REPORT 0 close
  fi
  case "$st" in
    working) landed=1 quiet_since= ;;
    blocked) # after --wait, the question just answered can linger for a moment
             [ -n "$waiting" ] && [ "$el" -lt "$quiet" ] || finish BLOCKED 3 ;;
    gone|'') finish GONE 6 ;;
    *)  # idle/done/unknown: a report can trail the last turn, so allow a grace
        # window; a prompt that never started is NOSTART once landing time is up
        if [ "$landed" = 1 ]; then
          quiet_since=${quiet_since:-$now}
          if [ $(( now - quiet_since )) -ge "$quiet" ]; then quota && finish QUOTA 5 close; finish NOREPORT 4; fi
        elif [ "$el" -ge "$land" ]; then
          quota && finish QUOTA 5 close; finish NOSTART 7
        fi ;;
  esac
  sleep "$poll"
done
