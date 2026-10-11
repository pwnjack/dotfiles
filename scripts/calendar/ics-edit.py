#!/usr/bin/env python3
"""Patch one iCalendar event file for the calendar card (run by cal.sh).

    ics-edit.py inspect   {"raw", "addresses", "occurrence"}
                          -> {"alert", "recurring", "invitation", "allDay", "hash"}
    ics-edit.py update    {"raw", "occurrence", "scope", "changes"} -> {"raw"}
    ics-edit.py delete    {"raw", "occurrence", "scope"}            -> {"raw"} ("" = remove the file)

One JSON request on stdin, one JSON answer on stdout; an error prints
{"ok": false, "error": ...} and exits 1. Everything the card does not edit is
kept. Times arrive as epochs and are written in the form the event already
uses: its own TZID (so a repeating event keeps its wall time across DST),
UTC, or floating local time. Python only because time zones and recurrence
exceptions need a real iCalendar library; khal already brings icalendar.

"addresses" are the account's own identities, normalised the way writable.sh
stores them; without it, "account" stands for mailto:<account>.
"""
import copy
import datetime as dt
import hashlib
import json
import os
import re
import sys
from zoneinfo import ZoneInfo

import icalendar

TIMED = {"0m": dt.timedelta(0), "5m": dt.timedelta(minutes=-5), "10m": dt.timedelta(minutes=-10),
         "15m": dt.timedelta(minutes=-15), "30m": dt.timedelta(minutes=-30), "1h": dt.timedelta(hours=-1),
         "2h": dt.timedelta(hours=-2), "1d": dt.timedelta(days=-1), "2d": dt.timedelta(days=-2),
         "1w": dt.timedelta(weeks=-1)}
ALLDAY = {"day0": dt.timedelta(hours=9), "day1": dt.timedelta(hours=-15),
          "day2": dt.timedelta(days=-1, hours=-15), "week": dt.timedelta(days=-6, hours=-15)}


def fail(message):
    print(json.dumps({"ok": False, "error": message}))
    sys.exit(1)


def local_zone():
    name = os.environ.get("TZ", "").lstrip(":")
    if not name:
        target = os.path.realpath("/etc/localtime")
        name = target.split("/zoneinfo/", 1)[1] if "/zoneinfo/" in target else "UTC"
    try:
        return ZoneInfo(name)
    except Exception:
        return ZoneInfo("UTC")


def is_date(value):
    return isinstance(value, dt.date) and not isinstance(value, dt.datetime)


def in_form(epoch, like):
    """`epoch` as a value of the same kind as `like` (DTSTART's value)."""
    if isinstance(like, dt.datetime) and like.tzinfo is not None:
        return dt.datetime.fromtimestamp(epoch, like.tzinfo)
    if isinstance(like, dt.datetime):                       # floating stays floating
        return dt.datetime.fromtimestamp(epoch, local_zone()).replace(tzinfo=None)
    return dt.datetime.fromtimestamp(epoch, dt.timezone.utc)  # was all-day: write UTC


def day(key):
    return dt.date.fromisoformat(key)


def normalise(value):
    """Match writable.sh's norm_address: lowercase, an http(s) URL reduced to
    its path, then one trailing "/" removed."""
    address = str(value).lower()
    match = re.match(r"^https?://[^/]*(/.*)?$", address)
    if match:
        address = match.group(1) or ""
    return address[:-1] if address.endswith("/") else address


def own_addresses(request):
    if "addresses" in request:
        return {normalise(a) for a in request["addresses"] if normalise(a)}
    account = str(request.get("account", "")).strip()
    return {normalise("mailto:" + account)} if account else set()


def invitation(master, mine):
    """Someone else organised it: the organiser is none of the account's own
    identities, by its value or by its EMAIL parameter."""
    organizer = master.get("ORGANIZER")
    if organizer is None or "ATTENDEE" not in master:
        return False
    names = {normalise(organizer)}
    email = organizer.params.get("EMAIL")
    if email:
        names.add(normalise("mailto:" + email))
    return not (names & mine)


def vevents(cal):
    return [c for c in cal.subcomponents if c.name == "VEVENT"]


def master_of(cal):
    for event in vevents(cal):
        if "RECURRENCE-ID" not in event:
            return event
    fail("The file has no main event")


def rid_for(master, occurrence):
    start = master.decoded("DTSTART")
    if is_date(start):
        return dt.datetime.fromtimestamp(occurrence, local_zone()).date()
    return in_form(occurrence, start)


def override_for(cal, rid):
    for event in vevents(cal):
        if "RECURRENCE-ID" in event and event.decoded("RECURRENCE-ID") == rid:
            return event
    return None


def alarms(event):
    return [c for c in event.subcomponents if c.name == "VALARM"]


def alert_of(event):
    found = alarms(event)
    if not found:
        return "none"
    table = ALLDAY if is_date(event.decoded("DTSTART")) else TIMED
    if len(found) == 1:
        trigger = found[0].decoded("TRIGGER")
        for key, value in table.items():
            if isinstance(trigger, dt.timedelta) and trigger == value:
                return key
    return "custom"


def replace(event, name, value):
    if name in event:
        del event[name]
    if value is not None:
        event.add(name, value)


def set_alert(event, alert, title):
    if alert == "custom":
        return
    event.subcomponents = [c for c in event.subcomponents if c.name != "VALARM"]
    table = ALLDAY if is_date(event.decoded("DTSTART")) else TIMED
    if alert in table:
        alarm = icalendar.Alarm()
        alarm.add("ACTION", "DISPLAY")
        alarm.add("DESCRIPTION", title)
        alarm.add("TRIGGER", table[alert])
        event.add_component(alarm)


def touch(event):
    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    replace(event, "DTSTAMP", now)
    replace(event, "LAST-MODIFIED", now)
    replace(event, "SEQUENCE", int(event.get("SEQUENCE", 0)) + 1)


def place_override(target, master, rid):
    """A new override sits on its own occurrence: DTSTART is the occurrence and
    DTEND keeps the series' length, so an all-day override is not left on the
    series' first date."""
    start = master.decoded("DTSTART")
    if "DTEND" in master:
        length = master.decoded("DTEND") - start
    elif "DURATION" in master:
        length = master.decoded("DURATION")
    else:
        length = dt.timedelta(days=1) if is_date(start) else dt.timedelta(0)
    replace(target, "DURATION", None)
    replace(target, "DTSTART", rid)
    replace(target, "DTEND", rid + length)


def set_times(event, changes, like, keep_date=None):
    """Write DTSTART/DTEND from `changes`; `keep_date` keeps a series' first date."""
    if "DURATION" in event:
        del event["DURATION"]
    if changes["allDay"]:
        replace(event, "DTSTART", day(changes["startDay"]))
        replace(event, "DTEND", day(changes["endDay"]) + dt.timedelta(days=1))
        return
    start = in_form(changes["start"], like)
    end = in_form(changes["end"], like)
    if keep_date is not None:
        length = end - start
        # A ZoneInfo works out the offset for the new date by itself.
        start = start.replace(year=keep_date.year, month=keep_date.month, day=keep_date.day)
        end = start + length
    replace(event, "DTSTART", start)
    replace(event, "DTEND", end)


def apply(event, changes, like, keep_date=None, times=True):
    replace(event, "SUMMARY", changes["title"])
    replace(event, "LOCATION", changes["location"] or None)
    if times:
        set_times(event, changes, like, keep_date)
    set_alert(event, changes["alert"], changes["title"])
    touch(event)


def parse(request):
    try:
        return icalendar.Calendar.from_ical(request["raw"])
    except Exception as error:
        fail(f"The event file could not be read: {error}")


def checked_changes(request):
    """The update's changes, or a failure that names what is missing or wrong."""
    changes = request.get("changes")
    if not isinstance(changes, dict):
        fail("The event changes are missing")
    missing = [key for key in ("title", "allDay", "alert") if key not in changes]
    if missing:
        fail(f"The event changes lack {', '.join(missing)}")
    if not isinstance(changes["title"], str) or not isinstance(changes["alert"], str) \
            or not isinstance(changes["allDay"], bool):
        fail("The event changes have the wrong types")
    try:
        if changes["allDay"]:
            day(changes["startDay"])
            day(changes["endDay"])
        else:
            for key in ("start", "end"):
                if isinstance(changes[key], bool) or not isinstance(changes[key], (int, float)):
                    raise TypeError(key)
    except (KeyError, TypeError, ValueError):
        fail("The event dates are not valid")
    return changes


def main():
    try:
        run()
    except Exception as error:
        fail(f"The event could not be changed: {error or type(error).__name__}")


def run():
    if len(sys.argv) != 2 or sys.argv[1] not in ("inspect", "update", "delete"):
        fail("Usage: ics-edit.py inspect|update|delete")
    request = json.loads(sys.stdin.readline())
    cal = parse(request)
    master = master_of(cal)
    recurring = "RRULE" in master or "RDATE" in master
    occurrence = request.get("occurrence") or 0
    scope = request.get("scope") or "all"

    if sys.argv[1] == "inspect":
        target = (override_for(cal, rid_for(master, occurrence)) if recurring and occurrence else None) or master
        print(json.dumps({"ok": True, "alert": alert_of(target), "recurring": recurring,
                          "invitation": invitation(master, own_addresses(request)),
                          "allDay": is_date(master.decoded("DTSTART")),
                          "hash": hashlib.sha256(request["raw"].encode()).hexdigest()}))
        return

    if sys.argv[1] == "delete":
        if not recurring or scope == "all":
            print(json.dumps({"ok": True, "raw": ""}))
            return
        rid = rid_for(master, occurrence)
        old = override_for(cal, rid)
        if old is not None:
            cal.subcomponents.remove(old)
        master.add("EXDATE", rid)
        touch(master)
        print(json.dumps({"ok": True, "raw": cal.to_ical().decode()}))
        return

    changes = checked_changes(request)
    if not changes["title"].strip():
        fail("An event needs a title")
    like = master.decoded("DTSTART")
    if not recurring:
        apply(master, changes, like)
    elif scope == "all":
        # Dates and All day are locked for a series: keep its first date, move the time.
        apply(master, changes, like, keep_date=None if is_date(like) else like.date(), times=not is_date(like))
    else:
        rid = rid_for(master, occurrence)
        target = override_for(cal, rid)
        if target is None:
            target = copy.deepcopy(master)
            for name in ("RRULE", "RDATE", "EXDATE", "RECURRENCE-ID"):
                if name in target:
                    del target[name]
            target.add("RECURRENCE-ID", rid)
            place_override(target, master, rid)
            cal.add_component(target)
        apply(target, changes, like, times=not is_date(like))
    print(json.dumps({"ok": True, "raw": cal.to_ical().decode()}))


if __name__ == "__main__":
    main()
