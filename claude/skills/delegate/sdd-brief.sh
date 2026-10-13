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
# 4 a template no longer fits (a placeholder missing or new, an empty prompt,
# or a report reference left in a review brief): read the plugin's template
# and update this script.
#
# Every value (titles, paths, file contents) is spliced in by Python as
# literal text in one pass: a plan title can never run as sed or shell code,
# and caller content is never mistaken for a template defect.
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
file=${*: -1}
[ -r "$file" ] || { echo "not readable: $file" >&2; exit 2; }
ws=$(bash "$sdd/scripts/sdd-workspace" "$plan")
brief=$ws/task-$n-brief.md report=$ws/task-$n-report.md

package() { # base head: verify the range, write the review package, print its path
  local out
  out=$(bash "$sdd/scripts/review-package" "$plan" "$1" "$2" 2>&1) || {
    case "$out" in *"empty commit range"*|*"not a descendant"*) echo "$out" >&2; exit 3 ;; esac
    echo "$out" >&2; exit 2; }
  out=${out##*wrote }; echo "${out%%:*}"
}

case "$kind" in
  implementer)
    bash "$sdd/scripts/task-brief" "$plan" "$n" "$brief" >/dev/null || exit 2
    tpl=$sdd/implementer-prompt.md base='' head='' diff='' ;;
  review|rereview)
    base=$3 head=$4; diff=$(package "$base" "$head")
    tpl=$sdd/task-reviewer-prompt.md; [ "$kind" = review ] || tpl=$sdd/re-review-prompt.md ;;
  final)
    base=$2 head=$3; diff=$(package "$base" "$head")
    tpl=$skills/requesting-code-review/code-reviewer.md ;;
esac
out=$ws/task-${n:-final}-$kind-$(date +%s%N).md

python3 - "$kind" "$tpl" "$out" "$file" "$n" "$brief" "$report" "${3:-}" "$base" "$head" "$diff" "$(readlink -f "$plan")" <<'PY'
import re, sys
kind, tpl, out, file, n, brief, report, workdir, base, head, diff, plan = sys.argv[1:]

def die(code, msg):
    print(msg, file=sys.stderr); sys.exit(code)

def read(path):
    try:
        with open(path, encoding="utf-8") as f: return f.read()
    except OSError as e: die(2, f"cannot read {path}: {e.strerror}")

# The template's prompt: the lines under "  prompt: |" up to the closing fence.
lines = read(tpl).split("\n")
if "  prompt: |" not in lines: die(4, f"template no longer fits: no '  prompt: |' block in {tpl}")
body = []
for l in lines[lines.index("  prompt: |") + 1:]:
    if l.startswith("```"): break
    body.append(l[4:] if l.startswith("    ") else l.strip())
text = "\n".join(body).strip("\n")
if not text: die(4, f"template no longer fits: empty prompt in {tpl}")

def section_out(text, heading, replacement=None):
    """Drop the '## heading' section (to the next '## '), or replace it."""
    out, skip, found = [], False, False
    for l in text.split("\n"):
        if l.startswith("## "):
            skip = l.startswith(heading)
            if skip:
                found = True
                if replacement: out.append(replacement)
                continue
        if not skip: out.append(l)
    if not found: die(4, f"template no longer fits: no '{heading}' section in {tpl}")
    return "\n".join(out)

tests = ("## Tests\n\nNo implementer report or test evidence is supplied, by design: the\n"
         "orchestrator re-runs the tests itself. Judge the code and its tests from the\n"
         "diff; run a focused test only on a specific doubt, and name it and the command.\n")
if kind == "review":
    text = section_out(text, "## What the Implementer Claims")
    text = section_out(text, "## Do Not Trust the Report")
    text = section_out(text, "## Tests", tests)
elif kind == "rereview":
    m = re.search(r"^Read the implementer.s report.*\n\[REPORT_FILE\]\n", text, re.M)
    if not m: die(4, f"template no longer fits: no implementer-report line in {tpl}")
    text = text[:m.start()] + text[m.end():]
    text = section_out(text, "## Tests", tests)

# What each kind's template must still hold, checked before any caller
# content goes in. A new placeholder, or a report reference left in a review
# template, means the plugin changed under this script.
need = {
    "implementer": ["Task N: [task name]", "[BRIEF_FILE]", "[REPORT_FILE]", "Work from: [directory]", "[Scene-setting"],
    "review": ["[BRIEF_FILE]", "[GLOBAL_CONSTRAINTS]", "[BASE_SHA]", "[HEAD_SHA]", "[DIFF_FILE]"],
    "rereview": ["[BRIEF_FILE]", "[FINDINGS]", "[FIX_BASE_SHA]", "[HEAD_SHA]", "[DIFF_FILE]"],
    "final": ["[DESCRIPTION]", "[PLAN_OR_REQUIREMENTS]", "[BASE_SHA]", "[HEAD_SHA]"],
}[kind]
missing = [t for t in need if t not in text]
if missing: die(4, f"template no longer fits: missing {' '.join(missing)} in {tpl}")
known = {t for t in need if re.fullmatch(r"\[[A-Z][A-Z_]+\]", t)} | {"[SHA]"}
new = sorted(set(re.findall(r"\[[A-Z][A-Z_]{2,}\]", text)) - known)
if new: die(4, f"template no longer fits: unfilled {' '.join(new)} in {tpl}")
if kind != "implementer" and re.search(r"\[REPORT_FILE\]|implementer.{0,2}s report|report\.md", text, re.I):
    die(4, f"template no longer fits: a review brief still points at the implementer's report ({tpl})")

# Fill every placeholder in one pass, with literal values.
supplied = read(file).rstrip("\n")
name = ""
if kind == "implementer":
    m = re.search(r"^#+ *Task \d+: *(.*)$", read(brief), re.M)
    name = m.group(1) if m else ""
    text = re.sub(r"^\[Scene-setting.*$", "\x00CTX\x00", text, count=1, flags=re.M)
values = {
    "Task N: [task name]": f"Task {n}: {name}",
    "Work from: [directory]": f"Work from: {workdir} (an isolated git worktree; commit your work there)",
    "\x00CTX\x00": supplied, "[GLOBAL_CONSTRAINTS]": supplied, "[FINDINGS]": supplied,
    "[BRIEF_FILE]": brief, "[REPORT_FILE]": report, "[DIFF_FILE]": diff,
    "[BASE_SHA]": base, "[FIX_BASE_SHA]": base, "[HEAD_SHA]": head,
    "[DESCRIPTION]": f"The whole branch for the plan below, {base}..{head}.",
    "[PLAN_OR_REQUIREMENTS]": f"Plan: {plan}. Review package (commits, stat, full diff): {diff}\n{supplied}",
}
text = re.sub("|".join(re.escape(k) for k in sorted(values, key=len, reverse=True)),
              lambda m: values[m.group(0)], text)

wiring = {
    "implementer": "Start the JSON report's summary with your status word (DONE, DONE_WITH_CONCERNS, BLOCKED or NEEDS_CONTEXT). Ask a question by stopping and asking in this session; the orchestrator answers here.",
    "review": "Report findings only; do not edit any file. In the JSON report, summary holds both verdicts (spec, quality); each finding is one string in concerns: severity, file:line, what is wrong, why it matters.",
    "rereview": "Report findings only; do not edit any file. In the JSON report, summary holds each finding verdict (ADDRESSED or NOT ADDRESSED) and the overall verdict; new breakage goes in concerns, one string each.",
    "final": "The orchestrator re-runs the tests itself. Report findings only; do not edit any file. In the JSON report, summary holds the overall verdict; each finding is one string in concerns: severity, file:line, what is wrong, why it matters.",
}[kind]
with open(out, "w", encoding="utf-8") as f:
    f.write(f"[LEAF WORKER — DO NOT DELEGATE]\n\n{text}\n\n## Report wiring\n{wiring}\n")
print(out)
PY
