# khal list --json prints one array per day; an event spanning days repeats
# on each. Map khal's fields to the calendar's one event shape and keep each
# event once. Formats are ISO (khal/config), so a timed stamp has a space.
# vdirsyncer and khal give colours as #RRGGBBAA; keep #RRGGBB, else "".
def color6: if test("^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$") then .[0:7] else "" end;
[ .[] | .[] ]
| map({
    uid: (.uid // ""),
    title: (.title // ""),
    location: (.location // ""),
    calendar: (.calendar // ""),
    color: ((."calendar-color" // "") | color6),
    start: .start,
    end: .end,
    allDay: ((.start | test(" ")) | not),
    recurring: ((."repeat-pattern" // "") != "")
  })
| unique_by([.calendar, .uid, .title, .start, .end])
| sort_by(.start)
