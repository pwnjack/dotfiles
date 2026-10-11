#!/usr/bin/env python3
"""List the events the account has declined (run by sync.sh, python3 -I).

    declined.py <data dir> <addresses file> <apple id>

Prints one rule per line, "<calendar>\t<UID>\t<key>", sorted and unique; cal.sh
hides the instances they name. An attendee entry counts for the account when it
is one of the account's own identities and its PARTSTAT is DECLINED. The keys:

    *            the main event (or a one-off) is declined: hide every instance
    <start>      an override is declined: hide the instance starting then
    !<start>     an override is not declined under a declined main event: show it

<start> is the local start in the normalised event format that khal's JSON
shows: "YYYY-MM-DD HH:MM", or "YYYY-MM-DD" for an all-day event. Unreadable
files are skipped; only a real error exits non-zero (sync.sh then keeps the
previous list).
"""
import datetime as dt
import icalendar
import os
import re
import sys


def normalise(value):
    """Copied from ics-edit.py's normalise() (its twin), which matches
    writable.sh's norm_address: lowercase, an http(s) URL reduced to its path,
    then one trailing "/" removed."""
    address = str(value).lower()
    match = re.match(r"^https?://[^/]*(/.*)?$", address)
    if match:
        address = match.group(1) or ""
    return address[:-1] if address.endswith("/") else address


def own_addresses(path, apple_id):
    try:
        with open(path, encoding="utf-8") as handle:
            lines = [normalise(line.strip()) for line in handle if line.strip()]
    except OSError:
        lines = []
    if not lines and apple_id.strip():
        lines = [normalise("mailto:" + apple_id.strip())]
    return {address for address in lines if address}


def display_name(folder):
    try:
        with open(os.path.join(folder, "displayname"), encoding="utf-8") as handle:
            name = handle.readline().strip()
    except OSError:
        name = ""
    return name or os.path.basename(folder)


def is_declined(event, mine):
    attendees = event.get("ATTENDEE", [])
    if not isinstance(attendees, list):
        attendees = [attendees]
    for attendee in attendees:
        if str(attendee.params.get("PARTSTAT", "")).upper() != "DECLINED":
            continue
        names = {normalise(attendee)}
        email = attendee.params.get("EMAIL")
        if email:
            names.add(normalise("mailto:" + email))
        if names & mine:
            return True
    return False


def instance_start(event):
    """The override's own start in khal's format: local wall time."""
    if "DTSTART" in event:
        value = event.decoded("DTSTART")
    elif "RECURRENCE-ID" in event:
        value = event.decoded("RECURRENCE-ID")
    else:
        return None
    if isinstance(value, dt.datetime):
        if value.tzinfo is not None:
            value = value.astimezone()
        return value.strftime("%Y-%m-%d %H:%M")
    return value.isoformat()


def rules_for(cal, mine):
    """(UID, key) rules for one file: its main events and their overrides."""
    masters = {}
    overrides = []
    for event in cal.walk("VEVENT"):
        if "UID" not in event:
            continue
        uid = str(event["UID"])
        if "RECURRENCE-ID" in event:
            overrides.append((uid, event))
        else:
            masters[uid] = masters.get(uid, False) or is_declined(event, mine)
    for uid, event in overrides:
        start = instance_start(event)
        if start is None:
            continue
        if is_declined(event, mine):
            yield uid, start
        elif masters.get(uid, False):
            yield uid, "!" + start
    for uid, declined in masters.items():
        if declined:
            yield uid, "*"


def declined_rules(path, mine):
    try:
        names = sorted(os.listdir(path))
    except OSError:
        return
    for name in names:
        if not name.endswith(".ics"):
            continue
        try:
            with open(os.path.join(path, name), "rb") as handle:
                cal = icalendar.Calendar.from_ical(handle.read())
        except Exception:
            continue
        yield from rules_for(cal, mine)


def main():
    if len(sys.argv) != 4:
        print("Usage: declined.py <data dir> <addresses file> <apple id>", file=sys.stderr)
        return 2
    data, addresses, apple_id = sys.argv[1:]
    mine = own_addresses(addresses, apple_id)
    rows = set()
    try:
        folders = sorted(entry.path for entry in os.scandir(data) if entry.is_dir())
    except OSError:
        folders = []
    for folder in folders:
        name = display_name(folder)
        for uid, key in declined_rules(folder, mine):
            rows.add(f"{name}\t{uid}\t{key}")
    for row in sorted(rows):
        print(row)
    return 0


if __name__ == "__main__":
    sys.exit(main())
