#!/bin/bash
# Classifies the account's iCloud collections into three state files in
# $CALENDAR_STATE_DIR, so the card never offers what cannot be used:
#   readonly   names of event calendars the account can only read
#   skip       names of collections without VEVENT (reminder lists)
#   addresses  the account's own calendar-user addresses, normalised, so the
#              card can tell which attendee is "me"
# Three PROPFINDs: principal -> calendar home (+ addresses) -> its calendars
# with their privileges. Credentials reach curl as a config on stdin (-K -),
# never argv. The files are replaced together, only after every request
# succeeded; on any failure the previous ones stay.
# shellcheck disable=SC2154  # cal_* paths come from lib.sh
set -euo pipefail
# shellcheck source=scripts/calendar/lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
id=$(cal_secret username); pw=$(cal_secret password)
[[ -n $id && -n $pw ]] || { echo 'No account stored' >&2; exit 1; }

# propfind <url> <depth> <props-xml> — the response body on stdout.
propfind() {
    local body="<?xml version=\"1.0\"?><d:propfind xmlns:d=\"DAV:\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\"><d:prop>$3</d:prop></d:propfind>"
    printf 'user = "%s:%s"\n' "$id" "$pw" | curl -sS --fail -K - -X PROPFIND -H "Depth: $2" \
        -H 'Content-Type: application/xml; charset=utf-8' --data-binary "$body" "$1"
}
# xp <xpath> — evaluated against stdin; empty when nothing matches.
xp() { xmllint --xpath "$1" - 2>/dev/null || true; }
# L <name> — a namespace-blind step, since every element is namespaced.
L() { printf "*[local-name()='%s']" "$1"; }
# norm_address — one line: lowercase, one trailing "/" off, an http(s) URL
# reduced to its path.
norm_address() {
    local a=${1,,}
    if [[ $a =~ ^https?://[^/]*(/.*)?$ ]]; then a=${BASH_REMATCH[1]}; fi
    printf '%s\n' "${a%/}"
}

principal=$(propfind https://caldav.icloud.com/ 0 '<d:current-user-principal/>' | xp "string(//$(L current-user-principal)/$(L href))")
[[ -n $principal ]] || { echo 'iCloud did not name the account principal' >&2; exit 1; }
[[ $principal == http* ]] || principal="https://caldav.icloud.com$principal"
account=$(propfind "$principal" 0 '<c:calendar-home-set/><c:calendar-user-address-set/>')
home=$(xp "string(//$(L calendar-home-set)/$(L href))" <<<"$account")
[[ -n $home ]] || { echo 'iCloud did not name the calendar home' >&2; exit 1; }
listing=$(propfind "$home" 1 '<d:displayname/><d:resourcetype/><c:supported-calendar-component-set/><d:current-user-privilege-set/>')

mkdir -p "$cal_state"
t_ro=$(mktemp "$cal_state/readonly.XXXXXX"); t_skip=$(mktemp "$cal_state/skip.XXXXXX"); t_addr=$(mktemp "$cal_state/addresses.XXXXXX")
trap 'rm -f -- "$t_ro" "$t_skip" "$t_addr"' EXIT

count=$(xp "count(//$(L calendar-user-address-set)/$(L href))" <<<"$account")
for ((i = 1; i <= ${count%.*}; i++)); do
    norm_address "$(xp "string((//$(L calendar-user-address-set)/$(L href))[$i])" <<<"$account")" >> "$t_addr"
done

count=$(xp "count(//$(L response))" <<<"$listing")
for ((i = 1; i <= ${count%.*}; i++)); do
    r="//$(L response)[$i]"
    [[ $(xp "count($r//$(L resourcetype)/$(L calendar))" <<<"$listing") == 1 ]] || continue
    name=$(xp "string($r//$(L displayname))" <<<"$listing")
    # A component set without VEVENT is a reminder list; none at all counts as events.
    if [[ $(xp "count($r//$(L supported-calendar-component-set)/$(L comp))" <<<"$listing") -gt 0 \
       && $(xp "count($r//$(L supported-calendar-component-set)/$(L comp)[@name='VEVENT'])" <<<"$listing") -eq 0 ]]; then
        printf '%s\n' "$name" >> "$t_skip"
        continue
    fi
    writes=$(xp "count($r//$(L privilege)/$(L write) | $r//$(L privilege)/$(L write-content) | $r//$(L privilege)/$(L all))" <<<"$listing")
    [[ ${writes%.*} -gt 0 ]] || printf '%s\n' "$name" >> "$t_ro"
done
mv -f "$t_ro" "$cal_state/readonly"
mv -f "$t_skip" "$cal_state/skip"
mv -f "$t_addr" "$cal_state/addresses"
