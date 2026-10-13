#!/usr/bin/env bash
# Build a pane worker's brief for one Superpowers subagent-driven-development
# role from the installed plugin's own templates, so no brief is edited by
# hand. Review kinds are blind by construction: the implementer's report and
# the sections that read it are removed. Prints the brief's path, which goes
# straight to pane.sh.
#
#   sdd-brief.sh implementer <plan> <task> <workdir> <context-file>
#   sdd-brief.sh review      <plan> <task> <base> <head> <constraints-file>
#   sdd-brief.sh rereview    <plan> <task> <fix-base> <head> <findings-file>
#   sdd-brief.sh final       <plan> <base> <head> <notes-file>
#
# Run it from the repository the plan lives in (the worktree). Briefs, review
# packages and report paths live in the plan's SDD workspace. SDD_SKILLS
# points at a Superpowers skills directory (default: the newest installed).
# Exit: 0 written, 2 usage or a bad argument, 3 an empty or reversed range,
# 4 a template no longer fits (a placeholder left, or a report left in a
# review brief): read the plugin's template and update this script.
set -euo pipefail

skills=${SDD_SKILLS:-$(ls -d "$HOME"/.claude/plugins/cache/*/superpowers/*/skills 2>/dev/null | sort -V | tail -1)}
sdd=$skills/subagent-driven-development
[ -d "$sdd" ] || { echo "Superpowers not found (SDD_SKILLS=$skills)" >&2; exit 2; }
usage() { grep '^#   sdd-brief.sh' "$0" | sed 's/^# *//' >&2; exit 2; }

kind=${1:-}; [ $# -ge 1 ] && shift
case "$kind" in
  implementer) [ $# -eq 4 ] || usage; plan=$1 n=$2 ;;
  review|rereview) [ $# -eq 5 ] || usage; plan=$1 n=$2 ;;
  final) [ $# -eq 4 ] || usage; plan=$1 n= ;;
  *) usage ;;
esac
[ -f "$plan" ] || { echo "no such plan: $plan" >&2; exit 2; }
for f in "${@: -1}"; do [ -r "$f" ] || { echo "not readable: $f" >&2; exit 2; }; done
ws=$(bash "$sdd/scripts/sdd-workspace" "$plan")
brief=$ws/task-$n-brief.md report=$ws/task-$n-report.md

# The prompt block of a template, de-indented.
prompt() { sed -n '/^  prompt: |$/,/^```$/p' "$1" | sed '1d;$d' | sed 's/^    //'; }
# Replace a placeholder line with a file's contents.
splice() { awk -v pat="$1" -v file="$2" 'index($0, pat) == 1 { while ((getline l < file) > 0) print l; next } { print }'; }
blind_tests='## Tests\n\nNo implementer report or test evidence is supplied, by design: the\norchestrator re-runs the tests itself. Judge the code and its tests from the\ndiff; run a focused test only on a specific doubt, and name it and the command.\n'
package() { # base head: verify the range, write the review package, print its path
  local out
  out=$(bash "$sdd/scripts/review-package" "$plan" "$1" "$2" 2>&1) || {
    case "$out" in *"empty commit range"*|*"not a descendant"*) echo "$out" >&2; exit 3 ;; esac
    echo "$out" >&2; exit 2; }
  out=${out##*wrote }; echo "${out%%:*}"
}

case "$kind" in
  implementer)
    workdir=$3 ctx=$4
    bash "$sdd/scripts/task-brief" "$plan" "$n" "$brief" >/dev/null || exit 2
    name=$(grep -m1 -E '^#+ *Task' "$brief" | sed -E 's/^#+ *Task [0-9]+: *//')
    body=$(prompt "$sdd/implementer-prompt.md" \
      | sed "s|Task N: \[task name\]|Task $n: $name|; s|\[BRIEF_FILE\]|$brief|; s|\[REPORT_FILE\]|$report|; s|Work from: \[directory\]|Work from: $workdir (an isolated git worktree; commit your work there)|" \
      | splice '[Scene-setting' "$ctx")
    wiring="Start the JSON report's summary with your status word (DONE, DONE_WITH_CONCERNS, BLOCKED or NEEDS_CONTEXT). Ask a question by stopping and asking in this session; the orchestrator answers here." ;;
  review)
    base=$3 head=$4; diff=$(package "$base" "$head")
    body=$(prompt "$sdd/task-reviewer-prompt.md" | awk -v t="$blind_tests" '
        /^## What the Implementer Claims/ || /^## Do Not Trust the Report/ { skip = 1; next }
        /^## Tests/ { skip = 1; printf "%s\n", t; next }
        /^## / { skip = 0 } !skip' \
      | sed "s|\[BRIEF_FILE\]|$brief|; s|\[BASE_SHA\]|$base|g; s|\[HEAD_SHA\]|$head|g; s|\[DIFF_FILE\]|$diff|" \
      | splice '[GLOBAL_CONSTRAINTS]' "$5")
    wiring='Report findings only; do not edit any file. In the JSON report, summary holds both verdicts (spec, quality); each finding is one string in concerns: severity, file:line, what is wrong, why it matters.' ;;
  rereview)
    base=$3 head=$4; diff=$(package "$base" "$head")
    body=$(prompt "$sdd/re-review-prompt.md" | awk -v t="$blind_tests" '
        /^Read the implementer.s report/ { getline; next }
        /^## Tests/ { skip = 1; printf "%s\n", t; next }
        /^## / { skip = 0 } !skip' \
      | sed "s|\[BRIEF_FILE\]|$brief|; s|\[FIX_BASE_SHA\]|$base|g; s|\[HEAD_SHA\]|$head|g; s|\[DIFF_FILE\]|$diff|" \
      | splice '[FINDINGS]' "$5")
    wiring='Report findings only; do not edit any file. In the JSON report, summary holds each finding verdict (ADDRESSED or NOT ADDRESSED) and the overall verdict; new breakage goes in concerns, one string each.' ;;
  final)
    base=$2 head=$3; diff=$(package "$base" "$head")
    req=$(mktemp); trap 'rm -f "$req"' EXIT
    { echo "Plan: $(readlink -f "$plan"). Review package (commits, stat, full diff): $diff"; cat "$4"; } > "$req"
    body=$(prompt "$skills/requesting-code-review/code-reviewer.md" \
      | sed "s|\[DESCRIPTION\]|The whole branch for the plan below, $base..$head.|; s|\[BASE_SHA\]|$base|g; s|\[HEAD_SHA\]|$head|g" \
      | splice '[PLAN_OR_REQUIREMENTS]' "$req")
    wiring='The orchestrator re-runs the tests itself. Report findings only; do not edit any file. In the JSON report, summary holds the overall verdict; each finding is one string in concerns: severity, file:line, what is wrong, why it matters.' ;;
esac

# A placeholder left over, or a report a blind reviewer must not see, means
# the plugin's template changed under this script.
left=$(grep -oE '\[[A-Z][A-Z_]{2,}\]' <<<"$body" | grep -vxF '[SHA]' || true)
[ -z "$left" ] || { echo "template no longer fits: unfilled $(echo $left)" >&2; exit 4; }
if [ "$kind" != implementer ] && grep -qiE "implementer.s report|$report" <<<"$body"; then
  echo "template no longer fits: a review brief still points at the implementer's report" >&2; exit 4
fi

out=$ws/task-${n:-final}-$kind-$(date +%s%N).md
{ echo '[LEAF WORKER — DO NOT DELEGATE]'; echo; printf '%s\n' "$body"; echo; echo '## Report wiring'; echo "$wiring"; } > "$out"
echo "$out"
