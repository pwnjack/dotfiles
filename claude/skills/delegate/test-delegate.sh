#!/usr/bin/env bash
# Fixture tests for codex-model.sh, and for pane.sh's opt-in gate and verdicts
# against a stub herdr. Synthetic catalogues only; never touches the real
# Herdr, Codex or Claude.
#   bash claude/skills/delegate/test-delegate.sh
set -uo pipefail
here=$(dirname "$(readlink -f "$0")")
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

# model <slug> <visibility> <priority> <efforts...>
model() {
  local slug=$1 vis=$2 pri=$3; shift 3
  jq -n --arg s "$slug" --arg v "$vis" --argjson p "$pri" \
    '{slug:$s, visibility:$v, priority:$p,
      supported_reasoning_levels: ($ARGS.positional | map({effort: ., description: "x"}))}' --args "$@"
}
catalogue() { jq -s '{models: .}' > "$tmp/$1.json"; }

all=(low medium high xhigh max ultra)
# Shaped like the real catalogue: a newer generation, an older one that still
# carries a codename the newer lacks, a codename-less legacy slug, a hidden row.
{ model gen9-astra list 1 "${all[@]}"; model gen9-sol list 2 "${all[@]}"; model gen9-luna list 3 low medium high
  model gen9-reserve hide 3 "${all[@]}"; model gen8.5-sol list 4 "${all[@]}"; model gen8.5-terra list 7 "${all[@]}"
  model gen8.5-luna list 8 "${all[@]}"; model gen8 list 12 low medium high xhigh; } | catalogue real
# Newest by version, not by priority; plain slug beats variants and snapshots.
{ model gen10-sol-mini list 5 "${all[@]}"; model gen10-sol-2031-01-01 list 4 "${all[@]}"
  model gen10-sol list 6 "${all[@]}"; model gen9-sol list 1 "${all[@]}"; model gen10-nova list 0 "${all[@]}"
  model gen9-astra list 2 "${all[@]}"; } | catalogue newer
# Only a variant exists in the newest generation.
{ model gen10-sol-mini list 3 "${all[@]}"; model gen9-sol list 1 "${all[@]}"; } | catalogue variant
# Effort shapes: only higher levels, none listed, plain strings, unknown names.
{ model gen9-sol list 1 high xhigh; model gen9-luna list 2 max ultra; model gen9-terra list 3 extra-high medium
  jq -n '{slug:"gen9-mars", visibility:"list", priority:4}'
  jq -n '{slug:"gen9-vega", visibility:"list", priority:5, supported_reasoning_levels:["low","medium"]}'
  model gen9-orion list 6 low high; } | catalogue efforts
{ model gen9-sol hide 1 "${all[@]}"; } | catalogue nolisted
# A new generation that ranks sol first must not gate sol.
{ model gen10-sol list 1 "${all[@]}"; model gen9-astra list 2 "${all[@]}"; model gen9-sol list 3 "${all[@]}"; } | catalogue solfirst
echo '[]' > "$tmp/arr.json"
echo '{not json' > "$tmp/broken.json"

# expect <catalogue> <alias> <effort> <want-exit> <want-stdout-joined>
expect() {
  local out rc
  out=$(CODEX_MODELS_CACHE="$tmp/$1.json" "$here/codex-model.sh" "$2" "$3" 2>/dev/null); rc=$?
  out=$(paste -sd' ' <<<"$out")
  if [ "$rc" = "$4" ] && [ "$out" = "$5" ]; then echo "ok   $1 $2 $3"
  else echo "FAIL $1 $2 $3: exit $rc want $4, out '$out' want '$5'"; fail=1; fi
}

expect real  sol      medium 0 "gen9-sol medium"      # newest generation wins
expect real  luna     xhigh  0 "gen9-luna high"       # clamped down to what it lists
expect real  terra    medium 0 "gen8.5-terra medium"  # only the older generation has it
expect real  astra    high   0 "gen9-astra high"
expect real  reserve  low    3 ""                     # hidden models are never picked
expect real  nova     low    3 ""                     # no such model: degrade
expect real  inherit  high   0 " high"
expect newer sol      low    0 "gen10-sol low"        # plain slug over -mini and a snapshot
expect variant sol    low    0 "gen10-sol-mini low"   # a variant still beats an older generation
expect efforts sol    low    0 "gen9-sol high"        # nothing at or below: clamp up
expect efforts luna   low    3 ""                     # only max/ultra listed
expect efforts terra  high   0 "gen9-terra medium"    # "extra-high" is not "high"
expect efforts mars   xhigh  0 "gen9-mars xhigh"      # no levels listed: pass through
expect efforts vega   high   0 "gen9-vega medium"     # levels as plain strings
expect efforts orion  medium 0 "gen9-orion high"      # never clamped down to low
expect efforts orion  low    0 "gen9-orion low"       # low when asked for
expect real  sol      ultra  2 ""
expect real  sol      max    2 ""
expect real  Sol      low    2 ""
expect real  gen9-sol low    2 ""                     # an alias, never a slug
expect nolisted sol   low    3 ""
expect arr   sol      low    3 ""
expect broken sol     low    3 ""
expect missing sol    low    3 ""

# expensive <alias-or-slug> <want-exit> — needs no catalogue, so none is given
expensive() {
  local rc; CODEX_MODELS_CACHE=/nonexistent "$here/codex-model.sh" --is-expensive "$1" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$2" ]; then echo "ok   is-expensive $1"
  else echo "FAIL is-expensive $1: exit $rc want $2"; fail=1; fi
}
expensive astra 0
expensive gen9-astra 0
expensive gen9-astra-pro-2031-06-30 0
expensive sol 1
expensive gen8.5-sol 1
expensive gen8.5-sol-mini 1                             # a variant of a standard name
expensive terra 1
expensive luna 1
expensive gen8 0                                        # no codename: not known to be standard
expensive nova 0                                        # a codename Codex ships later is opt-in

# pane.sh gate: argument errors and the opt-in gate exit 2 before Herdr is
# consulted; anything that passes them, without Herdr, exits 8 (NOHERDR).
echo brief > "$tmp/brief.md"
printf 'model = "gen8.5-sol"\n' > "$tmp/config-ok.toml"
printf 'model = "gen9-astra"\nmodel_reasoning_effort = "low"\n[tui]\nmodel = "x"\n' > "$tmp/config-astra.toml"
printf 'model = "gen9-astra-2031-06-30"\n' > "$tmp/config-snap.toml"
printf '[profiles.x]\nmodel = "gen9-astra"\n' > "$tmp/config-table.toml"
printf "model = 'gen9-astra'\n" > "$tmp/config-single.toml"
printf 'model = "gen8.5-sol"\nprofile = "big"\n[profiles.big]\nmodel = "gen9-astra"\n' > "$tmp/config-profile.toml"
printf 'model_reasoning_effort = "low"\n' > "$tmp/config-nomodel.toml"
gate() { env -u HERDR_ENV -u HERDR_PANE_ID -u DELEGATE_EXPENSIVE ${OPTIN:+DELEGATE_EXPENSIVE=1} \
  CODEX_MODELS_CACHE="${CACHE:-$tmp/real.json}" CODEX_CONFIG="${CONFIG:-$tmp/config-ok.toml}" \
  "$here/pane.sh" "$@" >/dev/null 2>&1; echo $?; }
check() { if [ "$1" = "$2" ]; then echo "ok   gate $3"; else echo "FAIL gate $3: exit $1 want $2"; fail=1; fi; }
b=$tmp/brief.md
check "$(gate codex medium slug "$b")"            2 "missing alias"
check "$(gate codex sol ultra slug "$b")"               2 "ultra refused"
check "$(OPTIN=1 gate codex astra ultra slug "$b")"     2 "ultra refused even with opt-in"
check "$(gate codex sol high slug)"                     2 "missing brief"
check "$(gate codex sol high slug /nonexistent)"        2 "unreadable brief"
check "$(gate codex sol high slug "$b" extra)"          2 "extra argument"
check "$(gate codex sol high a-slug-of-23-characters "$b")" 2 "slug over Herdr's name limit"
check "$(gate claude sonnet high a-slug-of-22-character "$b")" 2 "claude slug over Herdr's name limit"
check "$(gate claude sonnet medium slug "$b")"    8 "valid claude, no herdr"
check "$(gate claude haiku high slug "$b")"       8 "claude haiku, no herdr"
check "$(gate claude gpt-4 high slug "$b")"       2 "malformed claude alias"
check "$(gate claude fable high slug "$b")"       2 "fable refused without opt-in"
check "$(OPTIN=1 gate claude fable high slug "$b")" 8 "fable allowed with opt-in"
check "$(gate claude nova high slug "$b")"        2 "a Claude alias that ships later is opt-in"
check "$(OPTIN=1 gate claude nova high slug "$b")" 8 "a later Claude alias with opt-in"
check "$(gate claude sonnet slug "$b")"           2 "claude needs an effort"
check "$(gate claude sonnet max slug "$b")"       2 "max refused"
check "$(gate claude sonnet ultra slug "$b")"     2 "ultra refused for claude too"
check "$(gate bogus sol high slug "$b")"          2 "unknown kind"
check "$(gate)"                                   2 "no arguments"
check "$(env HERDR_ENV=1 HERDR_PANE_ID= CODEX_MODELS_CACHE="$tmp/real.json" CODEX_CONFIG="$tmp/config-ok.toml" \
  "$here/pane.sh" claude sonnet medium slug "$b" >/dev/null 2>&1; echo $?)" 7 "inside Herdr but unusable: NOSTART, not NOHERDR"
check "$(gate codex sol high Bad_Slug "$b")"            2 "slug with invalid characters"
check "$(gate codex sol high slug "$b")"                8 "valid, no herdr"
check "$(gate codex terra medium slug "$b")"            8 "older-generation alias"
check "$(gate codex astra high slug "$b")"              2 "astra refused without opt-in"
check "$(OPTIN=1 gate codex astra high slug "$b")"      8 "astra allowed with opt-in"
check "$(CACHE=$tmp/solfirst.json gate codex sol medium slug "$b")" 8 "sol ranked first in a new generation still launches"
check "$(gate codex --is-expensive astra slug "$b")"    2 "subcommand is not an alias"
check "$(CONFIG=$tmp/config-astra.toml gate codex inherit low slug "$b")" 2 "inherit onto astra refused"
check "$(CONFIG=$tmp/config-snap.toml gate codex inherit low slug "$b")" 2 "inherit onto an astra snapshot refused"
check "$(CONFIG=$tmp/config-astra.toml gate codex nova low slug "$b")" 2 "degrade onto astra refused"
check "$(CONFIG=$tmp/config-astra.toml OPTIN=1 gate codex inherit low slug "$b")" 8 "inherit onto astra with opt-in"
check "$(CONFIG=$tmp/config-table.toml gate codex inherit low slug "$b")" 2 "no top-level model: refused"
check "$(CONFIG=$tmp/config-nomodel.toml gate codex inherit low slug "$b")" 2 "no model key: refused"
check "$(CONFIG=$tmp/config-nomodel.toml OPTIN=1 gate codex inherit low slug "$b")" 8 "no model key with opt-in"
check "$(CONFIG=$tmp/config-single.toml gate codex inherit low slug "$b")" 2 "single-quoted astra refused"
check "$(CONFIG=$tmp/config-profile.toml gate codex inherit low slug "$b")" 2 "profile-selected astra refused"
check "$(CONFIG=$tmp/config-astra.toml CACHE=/nonexistent gate codex sol low slug "$b")" 2 "missing catalogue cannot fail open onto astra"
check "$(CONFIG=$tmp/config-astra.toml CACHE=$tmp/broken.json gate codex nova low slug "$b")" 2 "corrupt catalogue cannot fail open onto astra"
# A classifier that errors (here: jq failing on its codename query) must not
# read as "standard".
mkdir -p "$tmp/badjq"
printf '#!/bin/sh\ncase " $* " in *" -rn "*) exit 5 ;; esac\nexec %s "$@"\n' "$(command -v jq)" > "$tmp/badjq/jq"
chmod +x "$tmp/badjq/jq"
check "$(PATH="$tmp/badjq:$PATH" CONFIG=$tmp/config-astra.toml gate codex inherit low slug "$b")" 2 "classifier error cannot fail open onto astra"
check "$(PATH="$tmp/badjq:$PATH" gate codex sol low slug "$b")" 2 "classifier error refuses even a standard alias"
check "$(gate codex nova low slug "$b")"                2 "a codename that ships later is opt-in"
check "$(OPTIN=1 gate codex nova low slug "$b")"        8 "unknown alias with opt-in degrades onto the config model"
check "$(CACHE=/nonexistent gate codex sol low slug "$b")" 8 "missing catalogue degrades"

# pane.sh verdicts against a stub herdr. SCEN picks how the fake agent
# behaves; the third `agent get` while working is when it "finishes".
mkdir -p "$tmp/bin"
cat > "$tmp/bin/herdr" <<'STUB'
#!/usr/bin/env bash
S=$STATE
report='{"status":"complete","summary":"s","files_changed":[],"commands_run":[],"tests_run":[],"blockers":[],"concerns":[]}'
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[]}}' ;;
  "pane split") [ "$SCEN" = splitfail ] && echo '{}' || echo '{"result":{"pane_id":"p1"}}' ;;
  "pane close") touch "$S/closed" ;;
  "agent start") printf '%s\n' "$@" > "$S/start"; [ "$SCEN" = gate ] && echo "Do you trust this folder?" > "$S/screen"; exit 0 ;;
  "agent read") cat "$S/screen" 2>/dev/null ;;
  "agent send-keys") echo "$4" >> "$S/keys"; : > "$S/screen" ;;
  "agent prompt")
    n=$(( $(cat "$S/prompts" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$S/prompts"; echo "$4" > "$S/msg"
    rep=${4##*write your report to }; echo "${rep%% as JSON*}" > "$S/report"
    case "$SCEN" in
      nostart) ;;
      hooks|hooksresume) [ "$n" = 1 ] && echo "Hooks — 1 hook needs review" > "$S/screen"; echo working > "$S/status" ;;
      earlyblock) echo blocked > "$S/status" ;;
      idlequota) echo idle > "$S/status"; echo "■ You've hit your usage limit. Try again later." > "$S/screen" ;;
      *) echo working > "$S/status" ;;
    esac ;;
  "agent get")
    g=$(( $(cat "$S/gets" 2>/dev/null || echo 0) + 1 )); echo "$g" > "$S/gets"
    st=$(cat "$S/status" 2>/dev/null || echo idle)
    # --wait: the answered question lingers as blocked for two polls, then work resumes
    if { [ "$SCEN" = wait ] || [ "$SCEN" = keepwait ]; } && [ "$st" = blocked ] && [ "$g" -ge 2 ]; then st=working g=0; echo 0 > "$S/gets"; echo working > "$S/status"; fi
    if [ "$st" = working ] && [ "$g" -ge 3 ]; then
      case "$SCEN" in
        happy|wait|claude|keep|keepwait|resume) echo "$report" > "$(cat "$S/report")"; st=idle ;;
        # only a recovered prompt (escape, then exactly one resend) produces the report
        hooks|hooksresume) [ ! -s "$S/screen" ] && [ "$(cat "$S/prompts")" = 2 ] && { echo "$report" > "$(cat "$S/report")"; st=idle; } ;;
        quota|keepquota) st=idle; printf 'working\nYou have hit your usage limit. Try again later.\n' > "$S/screen" ;;
        mentions) st=blocked
          { echo "fixing the quota check, upgrade to the new usage limit text"; seq 20; echo "Allow command? y/n"; } > "$S/screen" ;;
        tailmention) st=blocked; printf 'Run: grep "usage limit reached" pane.sh\nAllow command? y/n\n' > "$S/screen" ;;
        noreport) st=idle ;;
        gone) exit 1 ;;
      esac
      echo "$st" > "$S/status"
    fi
    echo "{\"result\":{\"agent\":{\"agent_status\":\"$st\"}}}" ;;
esac
STUB
chmod +x "$tmp/bin/herdr"

# verdict <scenario> <want-exit> <want-first-word> <want-pane-closed:yes|no> [pane.sh args...]
verdict() {
  local sc=$1 want=$2 word=$3 close=$4; shift 4
  local st="$tmp/state-$sc" out rc closed=no
  mkdir -p "$st"
  [ $# -gt 0 ] || set -- codex sol medium "t-$sc" "$b"
  [ "$sc" = wait ] && { echo blocked > "$st/status"; echo "$tmp/handoff/w.json" > "$st/report"; }
  [ "$sc" = keepwait ] && { echo blocked > "$st/status"; echo "$tmp/handoff/kw.json" > "$st/report"; }
  out=$(env SCEN="$sc" STATE="$st" PATH="$tmp/bin:$PATH" HERDR_ENV=1 HERDR_PANE_ID=p0 HERDR_TAB_ID=t0 \
    DELEGATE_HANDOFF_DIR="$tmp/handoff" CODEX_MODELS_CACHE="$tmp/real.json" CODEX_CONFIG="$tmp/config-ok.toml" \
    DELEGATE_POLL=0.1 DELEGATE_QUIET=2 DELEGATE_LAND=3 DELEGATE_KEEP="${KEEP:-}" \
    "$here/pane.sh" "$@" 2>/dev/null); rc=$?
  [ -e "$st/closed" ] && closed=yes
  if [ "$rc" = "$want" ] && [ "${out%% *}" = "$word" ] && [ "$closed" = "$close" ]; then echo "ok   pane $sc -> $word"
  else echo "FAIL pane $sc: exit $rc want $want, verdict '${out%% *}' want $word, closed $closed want $close"; fail=1; fi
}
mkdir -p "$tmp/handoff"
verdict happy       0 REPORT   yes
verdict claude      0 REPORT   yes claude sonnet high t-claude "$b"
leaf='You are a leaf worker. Do not delegate, spawn subagents, or start other agents. Do the work yourself.'
if grep -qx -- claude "$tmp/state-claude/start" && grep -A1 -x -- --model "$tmp/state-claude/start" | grep -qx sonnet \
   && grep -A1 -x -- --effort "$tmp/state-claude/start" | grep -qx high \
   && grep -A1 -x -- --append-system-prompt "$tmp/state-claude/start" | tail -1 | grep -qxF -- "$leaf"
then echo "ok   pane claude: launched as a sonnet leaf worker"; else echo "FAIL pane claude: launch args $(cat "$tmp/state-claude/start")"; fail=1; fi
if grep -qx -- codex "$tmp/state-happy/start" && grep -A1 -x -- -m "$tmp/state-happy/start" | grep -qx gen9-sol
then echo "ok   pane codex: launched with the resolved model"; else echo "FAIL pane codex: launch args $(cat "$tmp/state-happy/start")"; fail=1; fi
# Claude workers start with Superpowers off: a leaf that brainstorms waits for
# an approval no one gives. Codex has no such switch for a remote plugin, so
# no dead override is passed.
if grep -A1 -x -- --settings "$tmp/state-claude/start" | tail -1 \
     | grep -qxF -- '{"enabledPlugins":{"superpowers@anthropic-plugin-directory":false}}'
then echo "ok   pane claude: Superpowers off in the worker"; else echo "FAIL pane claude: no plugin override"; fail=1; fi
if ! grep -q superpowers "$tmp/state-happy/start"
then echo "ok   pane codex: no dead plugin override"; else echo "FAIL pane codex: passes an override Codex ignores"; fail=1; fi
missing=
for k in status summary files_changed commands_run tests_run blockers concerns; do
  grep -q "\b$k\b" "$tmp/state-claude/msg" || missing="$missing $k"
done
if [ -z "$missing" ] && grep -q "write your report to $tmp/handoff/t-claude-" "$tmp/state-claude/msg"
then echo "ok   pane prompt: names the report path and every key"; else echo "FAIL pane prompt: missing$missing"; fail=1; fi
verdict hooks       0 REPORT   yes    # hook-review screen swallowed the first prompt
if [ "$(cat "$tmp/state-hooks/keys" 2>/dev/null)" = esc ] && [ "$(cat "$tmp/state-hooks/prompts")" = 2 ]
then echo "ok   pane hooks: one escape, one resend"; else echo "FAIL pane hooks: escape/resend not as expected"; fail=1; fi
verdict quota       5 QUOTA    yes
verdict idlequota   5 QUOTA    yes    # rejected before it ever started
verdict mentions    3 BLOCKED  no     # a task that talks about limits is not a quota hit
verdict tailmention 3 BLOCKED  no     # not even with the words at the bottom of the screen
verdict earlyblock  3 BLOCKED  no     # an approval question before the first poll
verdict noreport    4 NOREPORT no
verdict nostart     7 NOSTART  no
verdict gate        7 NOSTART  no
verdict splitfail   7 NOSTART  no
verdict gone        6 GONE     no
verdict wait        0 REPORT   yes --wait p1 "$tmp/handoff/w.json"   # stale blocked state is not a new block
verdict timeout     124 TIMEOUT no --wait p1 "$tmp/handoff/none.json" 0
# --resume: a follow-up prompt into a kept pane, with a fresh report path; the
# pane stays open for the next round.
printf 'Fix the finding: tests/x.sh:3 asserts nothing.\n' > "$tmp/fix.md"
verdict resume    0 REPORT  no --resume p1 "$tmp/fix.md"
if grep -qF 'Fix the finding: tests/x.sh:3 asserts nothing.' "$tmp/state-resume/msg" \
   && grep -q "write your report to $tmp/handoff/resume-p1-[A-Za-z0-9]*.json as JSON with exactly these keys" "$tmp/state-resume/msg"
then echo "ok   pane resume: message plus a fresh report path"; else echo "FAIL pane resume: prompt was '$(cat "$tmp/state-resume/msg" 2>/dev/null)'"; fail=1; fi
verdict hooksresume 0 REPORT no --resume p1 "$tmp/fix.md" 1   # a resume prompt swallowed by the hook screen
if [ "$(cat "$tmp/state-hooksresume/keys" 2>/dev/null)" = esc ] && [ "$(cat "$tmp/state-hooksresume/prompts")" = 2 ]
then echo "ok   pane resume hooks: one escape, one resend"; else echo "FAIL pane resume hooks: not recovered"; fail=1; fi
# Two resumes of one pane in the same second get different report paths.
uniq_report() { mkdir -p "$tmp/state-uniq"; env PATH="$tmp/bin:$PATH" STATE="$tmp/state-uniq" SCEN=nostart HERDR_ENV=1 \
  DELEGATE_HANDOFF_DIR="$tmp/handoff" DELEGATE_LAND=0 DELEGATE_POLL=0.1 \
  "$here/pane.sh" --resume p1 "$tmp/fix.md" 2>/dev/null | head -1 | grep -o 'report=[^ ]*'; }
r1=$(uniq_report); r2=$(uniq_report)
if [ -n "$r1" ] && [ "$r1" != "$r2" ]; then echo "ok   pane resume: a unique report path each time"
else echo "FAIL pane resume: report paths '$r1' and '$r2'"; fail=1; fi
check "$(gate --resume p1 /nonexistent)"           2 "resume needs a readable message"
check "$(gate --resume p1)"                        2 "resume needs a message file"
KEEP=1 verdict keep      0 REPORT  no     # kept open for a fix round
KEEP=1 verdict keepwait  0 REPORT  no --wait p1 "$tmp/handoff/kw.json"   # and again after the round
KEEP=1 verdict keepquota 5 QUOTA   yes    # a pane out of quota is closed regardless

exit $fail
