#!/usr/bin/env bash
# Claude Code status line — model, effort, context, 5h/7d rate limits.
# Adapted from https://github.com/fedddorov/claude-code-status-bar
# Wire up in ~/.claude/settings.json:
#   "statusLine": {"type": "command", "command": "bash ~/.config/claude/statusline.sh"}
# The session's time locale, kept for naming reset days before LC_ALL=C below.
time_locale=${LC_ALL:-${LC_TIME:-${LANG:-C}}}
export LC_ALL=C   # printf %f rejects "72.4" under comma-decimal locales
input=$(cat)
IFS=$'\x1f' read -r model effort used total win fiveh fiveh_at week week_at < <(
  jq -r '[
    (.model.display_name // "" | sub(" *\\(.*\\)$"; "")),
    (.effort.level // ""),
    (.context_window.used_percentage // ""),
    (.context_window | if .total_input_tokens == null and .total_output_tokens == null then ""
       else (.total_input_tokens // 0) + (.total_output_tokens // 0) end),
    (.context_window.context_window_size // 0 | if . > 0 then floor else "" end),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // "")
  ] | map(tostring) | join("\u001f")' <<<"$input"
)

fmt_tok() { awk -v n="$1" 'BEGIN{if(n>=1000000)printf"%.1fM",n/1000000;else if(n>=1000)printf"%.0fk",n/1000;else printf"%d",n}'; }
# seconds until an epoch timestamp, as 2d3h / 2h14m / 9m
fmt_left() { awk -v t="$1" -v now="$(date +%s)" 'BEGIN{s=t-now;if(s<0)s=0;d=int(s/86400);h=int(s%86400/3600);m=int(s%3600/60);if(d>0)printf"%dd%dh",d,h;else if(h>0)printf"%dh%dm",h,m;else printf"%dm",m}'; }

# ANSI palette
DIM=$'\033[2;37m'
B=$'\033[1m'
R=$'\033[0m'
GRN=$'\033[38;5;108m'   # soft sage green
YEL=$'\033[38;5;179m'   # muted gold
ORG=$'\033[38;5;173m'   # soft amber
RED=$'\033[38;5;167m'   # soft rose-red
BLU=$'\033[38;5;110m'   # soft steel blue: context's base, apart from the usage bars
# rate-limit color: green < 50, yellow >= 50, orange >= 80, red >= 90
hue() { awk -v p="$1" -v g="$GRN" -v y="$YEL" -v o="$ORG" -v r="$RED" 'BEGIN{if(p>=90)print r;else if(p>=80)print o;else if(p>=50)print y;else print g}'; }
# context color: blue < 50, yellow >= 50, orange >= 70, red >= 85
hue_ctx() { awk -v p="$1" -v g="$BLU" -v y="$YEL" -v o="$ORG" -v r="$RED" 'BEGIN{if(p>=85)print r;else if(p>=70)print o;else if(p>=50)print y;else print g}'; }
# reasoning-effort color: green = low, yellow = medium, red = high/xhigh/max
hue_eff() { case "$1" in low) echo "$GRN";; medium) echo "$YEL";; high|xhigh|max) echo "$RED";; *) echo "$DIM";; esac; }

# FiraCode's own progress bar (U+EE00-EE05): an outlined, round-ended bar
# whose cells fill from the left. Empty left/middle/right, then filled
# left/middle/right. Written as UTF-8 bytes: private-use glyphs typed
# literally vanish in some tools, and $'\U…' is not expanded under LC_ALL=C.
PB=($'\xee\xb8\x80' $'\xee\xb8\x81' $'\xee\xb8\x82'
    $'\xee\xb8\x83' $'\xee\xb8\x84' $'\xee\xb8\x85')
BAR_CELLS=8

# bar <percent> <color>: the whole bar in one colour, so the outline stays
# continuous where the fill stops. The caps are mostly border, so k filled
# cells look like (k-0.4)/(n-0.6) of the bar, not k/n (measured from the
# rendered glyphs); the cell count is the one whose look is nearest the
# percent. Plain k/n rounding drew 76% as five of six cells, which looked 86%.
bar() {
  local filled i k out=""
  filled=$(awk -v u="$1" -v n="$BAR_CELLS" 'BEGIN{f=int(u/100*(n-0.6)+0.4+0.5);if(u<=0)f=0;if(f<0)f=0;if(f>n)f=n;print f}')
  for ((i = 1; i <= BAR_CELLS; i++)); do
    if [ "$i" -eq 1 ]; then k=0; elif [ "$i" -eq "$BAR_CELLS" ]; then k=2; else k=1; fi
    [ "$i" -le "$filled" ] && k=$((k + 3))
    out+=${PB[$k]}
  done
  printf '%s%s%s' "$2" "$out" "$R"
}

# rate-limit segment: label, percent, reset epoch
# clock time of an epoch, with the weekday when it is not today; 12 h when
# options/clock says so, like the bar and the desktop clock
fmt_at() {
  local f='%H:%M'
  [ "$(cat "$HOME/.config/options/clock" 2>/dev/null)" = 12h ] && f='%-I:%M%p'
  [ "$(date -d "@$1" +%F)" = "$(date +%F)" ] || f="%a $f"
  LC_ALL=$time_locale date -d "@$1" +"$f"
}

limit() {
  local c; c=$(hue "$2")
  printf '%s%s%s %s %s%.0f%%%s' "$DIM" "$1" "$R" "$(bar "$2" "$c")" "$c" "$2" "$R"
  [ -n "$3" ] && printf ' %s%s · %s%s' "$DIM" "$(fmt_left "$3")" "$(fmt_at "$3")" "$R"
}

sep="${DIM} │ ${R}"
parts=()

head=""
[ -n "$model" ] && head="${B}${model}${R}"
if [ -n "$effort" ]; then
  ec=$(hue_eff "$effort")
  head="${head:+$head }${ec}●${R} ${ec}${effort}${R}"
fi
[ -n "$head" ] && parts+=("$head")

if [ -n "$used" ]; then
  cc=$(hue_ctx "$used")
  ctx="${DIM}ctx${R} $(bar "$used" "$cc") ${cc}$(printf '%.0f' "$used")%${R}"
  [ -n "$total" ] && ctx="${ctx} ${B}$(fmt_tok "$total")${R}${win:+${DIM}/$(fmt_tok "$win")${R}}"
  parts+=("$ctx")
fi

[ -n "$fiveh" ] && parts+=("$(limit 5h "$fiveh" "$fiveh_at")")
[ -n "$week" ]  && parts+=("$(limit 7d "$week" "$week_at")")

out=""
for p in "${parts[@]}"; do out="${out:+$out$sep}$p"; done
printf '%s\n' "$out"
