# Calendar: iCloud on the bar and in a card

Your iCloud calendars show on the bar, beside the clock, as the next event. The
clock and the next event form one capsule, and each opens the same Quickshell
card in a different view. The card lists the month, the coming week, and a day
at a time. It also adds, edits and deletes events, and those changes sync back
to the iPhone.

Only iCloud is supported. The calendar copy lives in
`~/.local/share/calendars/icloud/` and never in the repository. Dates and
weekdays follow `LC_TIME`, and the 12 or 24 hour clock follows `options/clock`,
the same two settings the clock uses.

## Setup

Apple requires an app-specific password for third-party CalDAV clients. Create
one at account.apple.com, under Sign-In and Security, then sign in with either
of these methods.

- **Settings panel (`Super + I`).** Open the Calendar page, enter your Apple ID
  and the app-specific password, and choose *Sign in*. The password goes to the
  helper on stdin and into the GNOME keyring. The helper then discovers the
  calendars, records which of them are read-only, enables the sync timer and
  syncs once. Signed in, the page's Account group names the account type
  (iCloud) and the address, then the sync state with *Sync now* (it reads
  *Syncing…* until the sync records its attempt), then *Sign out*. Sign out is
  red and asks for a second press, and that confirmation lapses after five
  seconds.
- **Terminal fallback.** Run `scripts/calendar/setup.sh --sign-in`. It asks for
  the same two values, with the password hidden, and does the same steps.

`scripts/calendar/setup.sh` without arguments is what `install.sh` runs. It
never prompts. With an account already stored, it links and enables the timer.
Without one, it prints a pointer to the panel. `setup.sh --sign-out` clears the
keyring entries, disables and stops the timer, and deletes the local copy, the
state files, the vdirsyncer status and the `agenda.json` and `status.json`
runtime files. It keeps `draft.json`, and the timer's unit links stay in place,
so a sign-out is not a complete removal. The sign-out first stops the timer and
the sync service, then waits up to two minutes for a running sync to finish and
for a running render (which reads and publishes `agenda.json`) to end. If either
still holds its lock, the sign-out refuses, and it removes nothing.

## How it works

The data path has one direction for reading and one for writing, both local
first:

```
iCloud ⇄ vdirsyncer ⇄ ~/.local/share/calendars/icloud/ ⇄ khal ⇄ cal.sh ⇄ bar and card
```

- **`sync.sh` is the normal sync path.** The timer, the card when it opens, an
  add or edit that needs pushing, the bar's right-click, and the panel's *Sync
  now* all run it. It takes a lock, so two syncs never overlap. The card's
  adds, edits and deletes take the same lock, for up to 15 seconds; when a sync
  holds it, the write is refused and the file is left as it was. It runs
  `vdirsyncer metasync` and `vdirsyncer sync`, discovers the calendars once a
  day, and rebuilds the declined list. Then it renders `agenda.json` and
  `status.json` in `$XDG_RUNTIME_DIR/calendar/`, and sends Waybar signal 12. A
  render that fails leaves the last `agenda.json` in place and turns a sync that
  would have been `ok` into a failed one, with `cal.sh`'s message. `sync.sh
  --render` exits 1 in that case, which is what the panel rolls an option back on.
  A sync whose account is removed while it runs writes nothing, and a render whose
  account is removed while it reads publishes nothing.
  `sync.sh --render` does the rendering and the signal with no network at all.
- **The sign-in exception.** `setup.sh --sign-in` runs `vdirsyncer discover`
  and `writable.sh` itself, outside the sync lock, before it enables the timer
  and syncs once. The daily discovery inside `sync.sh` runs `writable.sh` under
  the lock, but `writable.sh`'s three PROPFINDs use `curl` directly, so the lock
  does not serialise all network activity.
- **The timer** (`calendar-sync.timer`) runs two minutes after login and then
  every 15 minutes. The unit files are tracked and linked with
  `systemctl --user link`, not copied.
- **Failures.** `sync.sh` classifies a failed run from its error lines first,
  which are lines starting with `error` or `critical`, as *Sign-in rejected* (a
  word-bounded 401 or *unauthorized*), *iCloud is unreachable* (name resolution,
  a refused or reset connection, a timeout), or otherwise a message. Without any
  error line, it classifies from the whole output. The message is the last
  nonblank line of those lines, cut to 160 characters, or *Sync failed* when
  that is blank. The notification fires whenever the previous recorded state was
  not a failure. That covers the change from success, and a first failure before
  any success. A run of consecutive failures stays silent.
- **`cal.sh` is the only reader and writer of the local copy through khal.** It
  prints the card's JSON: `range`, `day`, `month`, `year`, `calendars`, `add`,
  `inspect`, `update` and `delete`. The ISO date formats in `khal/config` are
  what it parses. Everything a person reads is localised by the bar script and
  the card instead.
- **Read-only calendars and reminder lists.** `writable.sh` runs three
  PROPFINDs against iCloud after each discovery. It records calendars with no
  write privilege in `$CALENDAR_STATE_DIR/readonly`, and collections without
  VEVENT (the iCloud Reminders lists) in `skip`. `cal.sh` drops the skipped
  collections everywhere. It also stores the account's own calendar addresses in
  `addresses`, so the card can tell which attendee is you. Credentials reach
  `curl` on stdin, never in its arguments.
- **Colours.** iCloud sends colours as `#RRGGBBAA`. `cal.sh` reduces them to
  `#RRGGBB`, because Qt reads eight hex digits as ARGB. Any other value becomes
  empty, and the views use the accent instead.

### The bar capsule

The clock and `custom/agenda` sit in one `group/calendar`, styled as a single
capsule with a thin divider. Hovering tints only the segment under the pointer.
Neither segment has a lit state. Clicking the clock opens the card on the
month. Clicking the pill opens it with the coming week unfolded. Hovering
previews without a click: the clock's tooltip is Waybar's month calendar (the
wheel moves its month, the middle button shows the year), and the pill's is
the shown event in full, with its whole title, its time range, its calendar and
its location. It names the day when the event is not within today, and both
days when it runs past midnight.

`scripts/waybar/agenda-bar.sh` reads only `agenda.json`, `options/bar-agenda`
and `options/clock`. It runs once a minute and starts no Python and no network
access. It shows the first match of these rules:

1. An event in progress: `now · Dentist`, with class `now`.
2. A timed event starting within the mode's window: `18:00 Dentist`. In `next`
   mode an event on a later day shows its date, as `sab 17 · Dentist`.
3. An all-day event today: `Mum's birthday`.
4. Nothing. The module is hidden.

It also hides with no account, with no `agenda.json`, or in `hidden` mode, and
in that last case it does no work at all. Titles longer than 24 characters are
cut with an ellipsis, and the text is Pango-escaped.

The Bar page sets the mode in `options/bar-agenda`:

| Mode | Shows |
|---|---|
| `soon` (default) | In progress, or starting within 12 hours |
| `today` | In progress, or starting before midnight |
| `next` | In progress, or the next timed event in the snapshot |
| `hidden` | Nothing |

The bar reads only the snapshot that `sync.sh` renders: the eight days from
today. So `next` cannot show an event beyond that window, however far away it
is. Inside the window, `next` applies no further cut-off.

### The card

The card is one layer, centred on the monitor rather than on the capsule. Its
horizontal position comes from the window and card widths alone, and the code
never measures the capsule. Waybar's centre group also holds `custom/weather`,
so the capsule's centre need not be the monitor's. Its views change height with
a short animation and never move. It draws from
`agenda.json` at once and starts a sync in the background. The header then
moves from *syncing…* to *iCloud · synced just now* (or *synced N min ago*), and
the views refresh.

The header shows the long date, the sync status, a **Today** button when you
have browsed to another month or the year view, and **+**. The views are:

- **Month.** A localised week row, starting on the locale's first day. Today is
  filled, and a dot marks each day with events. The wheel moves a month, and
  the arrow keys move a day focus. Return opens the day. The month name opens
  the year view, with twelve months and their event counts. The arrows sit over
  the first and last weekday columns.
- **Upcoming.** Folded, it is one bar: *Next · 18:00 Dentist · +3 more*, or
  *Nothing in the next 7 days*. With something to list, a click anywhere on the
  bar unfolds it, and its chevron stays in the same place and turns as it folds
  and unfolds. Unfolded, the bar reads *Upcoming · 7 days* and the list follows,
  under *Today*, *Tomorrow* and the date. Each event shows its time range, its
  calendar colour and its title, and hovering shows its details.
- **Day.** It replaces Upcoming while a day is selected, under a bar of the
  same shape that names the day. The bar's **×**, Esc, or a second click on the
  same day closes it and puts Upcoming back, and the month stays where it is.
  It has that day's timeline (only when the day has a timed event) and its
  events, and a *New event on …* row. A click on the timeline's free space does
  nothing: **+** and *New event on …* are the only ways to start an event.

Clicking an event in Upcoming, in the day view or on a timeline block opens the
sheet in edit mode. Hovering only previews it.

The transition table below is what `quickshell/calendar/model.mjs` implements,
and each segment owns its view:

| You do | Card closed | Open, Upcoming folded | Open, Upcoming unfolded |
|---|---|---|---|
| Click clock | open, folded | close | fold (stay open) |
| Click event pill | open, unfolded | unfold (stay open) | close |
| Super+Shift+E | open on the sheet | switch to the sheet; Esc returns | same |
| Esc | — | one level back: picker → sheet → day view → year view → close | same |
| Wheel over month | — | previous/next month (years in year view) | same |
| Click outside | — | close; a sheet with a title becomes a draft | same |

With no account, the month still works. It shows a *Set up iCloud in Settings ›*
line in place of Upcoming, and the **+** button is disabled.

### The new-event sheet

The sheet's top bar reads *Cancel · New event · Add*. Its rows are:

1. **Title** (required, so Add stays disabled while it is blank) and
   **Location** (optional).
2. **All day**, then **Starts** and **Ends**, each a date pill and a time
   pill, and then the timeline.
3. **Calendar** (writable calendars only, with their colour) and **Alert**.

The defaults are the next full hour as the start, one hour as the duration
(`options/calendar-duration`), the calendar in `options/calendar-default` or the
first writable one, and the alert in `options/calendar-alert` (15 minutes unless
set). Moving the start moves the end and keeps the duration. Editing the end
changes the duration. An end before the start shows the end struck through and
disables Add.

A time pill takes `18`, `18:00`, `18.30` or `6pm`, typed into a field the same
size as the pill, and the wheel or the arrow keys step it by 15 minutes. A date
pill slides open an inline month picker with busy dots. Calendar and Alert open
dropdowns that float over the sheet, under their pill or above it when the sheet
has no room below, and move nothing else; the arrow keys and Return choose, and
a click outside only closes them. Only one pill is open at a time. Esc closes an
open picker or dropdown before it closes anything else. With **All day** on, the
times disappear, Ends is the last day, inclusive, and the alert presets become
*None*, *On the day (09:00)*, *1 day before (09:00)*, *2 days before (09:00)*
and *1 week before (09:00)*. The timed presets run from *None* to *1 week
before*, with *At time of event*.

The **timeline** shows the day's events as blocks in their calendar colours,
and the new event as an accent outline. Its window is 08–22, stretched to the
earliest and latest times involved and rounded out to whole hours, and it is
clamped to 00–24. Overlapping events fill a second lane, and a block's details
appear on hover. A click on a free gap moves the new event there, snapped to
the quarter hour. The hour labels run every four hours, or every six on a
window longer than 16 hours. The strip measures them, so no two ever touch, and
one that would crowd the end label gives way to it. Below the timeline, lines name each overlap, as *⚠ Overlaps
Calcetto 20:00–22:30*, and *Also that day* lists the all-day events, which never
clash with timed ones. Overlaps warn and never block.

Adding goes through `model.mjs`, which builds the VEVENT in UTC. It escapes the
summary and location, writes all-day events as `VALUE=DATE` with an exclusive
end, and adds a `VALARM` for the chosen alert. The card then runs `cal.sh add`,
which writes a temporary file and calls `khal import --batch -a <calendar>`.
It does not use `khal new`, which splits the summary on ` :: ` and turns the
text after it into the description. The new event is highlighted briefly, and
a sync starts in the background to push it to iCloud.

Closing a sheet that has a title saves a draft to
`$XDG_RUNTIME_DIR/calendar/draft.json`. The draft comes back the next time the
sheet opens, and Cancel or a successful Add clears it. If the local save fails,
the sheet stays open and the error shows under Add.

## Editing and deleting

Opening an event calls `cal.sh inspect`. It reads the file once and returns the
current alert, which is a preset id, `none`, or `custom`. Custom means several
alarms, one that matches no preset, one set to fire from the end of the event,
one that is not a display alarm, or one that repeats or has a duration. It also returns whether the event repeats,
whether it is an invitation, whether it is all-day, and a SHA-256 hash of the
file. The sheet then opens with the event's values, under *Cancel · Edit event
· Done*, with a red *Delete event* at the bottom.

- **Read-only.** Events in a read-only calendar, and invitations, open the same
  sheet with every field disabled and no Delete. The sheet shows *Read-only
  calendar*, or *Invitation · read-only here*. An invitation
  is an event whose ORGANIZER is not one of the account's own addresses.
- **What can change.** The title, location, start and end, the all-day flag,
  the alert and the calendar. A repeating event keeps its dates and its all-day
  flag fixed. Its time of day, duration, title, location, alert and calendar can
  still change, and a calendar change applies to the whole series.
- **Alert.** *Custom (kept)* is shown and preserved when the alarms match no
  preset. Choosing a preset replaces every alarm with that one, and *None*
  removes them. An edit that leaves the alert as it was, such as a change of
  title, leaves the alarms exactly as they are.
- **Done.** A one-off event saves at once. A repeating one asks *This event
  only* or *All events*, and asks *All events* alone when the calendar changed.
  *This event only* writes a `RECURRENCE-ID` override for that date, or updates
  the existing override. *All events* changes the series, keeps its first date
  and changes only its time of day. The series' times are written only when
  the times were moved, so a title, location or alert edit opened from an
  override leaves them alone.
- **Delete.** This confirms with *Delete event?*. A repeating event asks *This
  event only*, which adds an `EXDATE` and drops any override for that date, or
  *All events*, which removes the file.

`cal.sh update` and `cal.sh delete` first compare the hash from `inspect`. If
the file changed elsewhere in the meantime (another device, through iCloud),
they refuse with *This event changed elsewhere since you opened it; open it
again*. `scripts/calendar/ics-edit.py` then
patches the parsed file. Python handles this because time zones and recurrence
exceptions need a real iCalendar library, and khal already brings `icalendar`.
The patch keeps the event's own `TZID`, so a repeating event keeps its wall time
across the DST change, and it keeps every property it does not change. It bumps
`SEQUENCE` and updates `DTSTAMP` and `LAST-MODIFIED`. The new file is written to
a temporary name and renamed over the old one, which gives it a new inode.
vdirsyncer notices that change. A calendar change moves the file to the other
calendar's folder, with the same UID.

In edit mode the timeline never counts the event as clashing with itself, and
it draws the event only once, as the draft, never as a block under it. The
edit then goes through the same local-first path as an add.

Declined invitations are hidden everywhere by default: the bar, the dots, the
day view and the timeline. The Calendar page's *Show declined invitations*
switch (`options/calendar-declined`, `enabled` to show them) lists them again
without touching the rules, and the change re-renders the bar at once. `scripts/calendar/declined.py` runs after each sync. It finds the
attendee entries that match one of the account's addresses and are
`PARTSTAT=DECLINED`. It writes one rule per occurrence into
`$CALENDAR_STATE_DIR/declined`, keyed on the local start. Nothing is changed in
iCloud. A declined repeating invitation has one main rule, and its overrides
get their own. Those are the old invitations that repeat daily.

## Localisation

Names, order and the first day of the week come from `LC_TIME`. The bar script
formats with the session locale. The card reads `LC_ALL`, then `LC_TIME`, then
`LANG`, and passes the result to Qt as `CALENDAR_LOCALE`. The clock format
comes from `options/clock`. UI words are English, as in the rest of the panel.

## Error states

| Situation | What you see |
|---|---|
| No account | The pill is hidden. The card shows the month with *Set up iCloud in Settings ›*, and Add is disabled. |
| Offline | The header shows *Offline · showing events from 14:05*. The local copy is shown. |
| Sign-in rejected | The header shows *Sign-in rejected · Fix in Settings*. One notification appears on the change to failure. The doctor warns. |
| Local save fails | The sheet stays open, with the error under Add. Nothing is lost. |
| Read-only calendar | It is left out of the Calendar menu, and its events open read-only. |
| Changed on another device | Done or Delete is refused, with *This event changed elsewhere since you opened it; open it again*. |
| Edit cannot be written | The sheet stays open with the error. The file is untouched, because the write is atomic. |
| A sync is running | An add, edit or delete waits up to 15 seconds for the sync, then is refused with *A sync with iCloud is running; try again in a moment*. The file is untouched. |
| A render fails | The header shows the sync as failed, with khal's message, and the bar keeps its last agenda. An option change that needed the render is rolled back. |
| Tools missing | `sync.sh` records *vdirsyncer is not installed*, or *Calendar tools not installed* when khal is missing, as a failed sync of kind tool, and the header shows that message. With khal missing it also removes `agenda.json`, so the pill hides. `cal.sh` answers *khal is not installed*, which a read treats as no events and an add or edit shows under Add. The doctor reports each missing tool as an error. With only vdirsyncer missing, the pill keeps the last `agenda.json` that rendered. |
| DST | New timed events are written in UTC and shown in local time. Existing events keep their own time zone (`TZID`) or floating time. An edit writes its new times in that same form, so a repeating event keeps its wall time across DST. An all-day event that becomes timed is written in UTC. |

## Files and options

| Path | Purpose |
|---|---|
| `vdirsyncer/config` | Pairs iCloud with the local copy. Tracked. |
| `khal/config` | Reads the local copy, with ISO formats. Tracked. |
| `scripts/calendar/sync.sh` | The normal sync path, and rendering. |
| `scripts/calendar/cal.sh` | The reader and writer of the local copy, through khal. |
| `scripts/calendar/ics-edit.py`, `declined.py` | Patch an event, and scan declined invitations. Python, for `icalendar`. |
| `scripts/calendar/writable.sh` | Classifies calendars into read-only, skipped and addresses. |
| `scripts/calendar/setup.sh` | Signs in and out, and enables the timer. |
| `scripts/calendar/calendar-sync.{service,timer}` | The sync unit and its schedule. Tracked. |
| `scripts/waybar/agenda-bar.sh` | Renders the next-event pill. |
| `scripts/hyprland/calendar-card.sh` | Launches or toggles the card (`month`, `upcoming`, `new`). |
| `quickshell/calendar/` | The card, its views and `model.mjs`, which holds the transition table. |
| `options/bar-agenda` | The pill's mode. Tracked. |
| `options/calendar-hidden`, `-default`, `-alert`, `-duration`, `-declined` | The calendars to hide, the default calendar, alert and duration, and whether declined invitations show. Untracked, because calendar names are personal. |

The runtime files are `agenda.json`, `status.json` and `draft.json` in
`$XDG_RUNTIME_DIR/calendar/`. The state files are `readonly`, `skip`,
`addresses`, `declined` and `discovered` in `~/.local/state/calendar/`.

## Checks

- `./test.sh` runs the suites for the scripts, the card and the bar. The
  calendar suites run against fakes for vdirsyncer, khal, secret-tool, curl and
  notify-send, and against fixtures shaped like iPhone events. No test touches
  the keyring or the real calendar copy.
- `./doctor.sh` runs `check_calendar`. Once an account is stored, it warns when
  the timer is not enabled, when the last sync failed, or when the last success
  is more than an hour old. It errors when `khal` or `vdirsyncer` is missing. It
  reads the tool names from `install.sh`, and it stays silent without an account.
- The live round trip: add an event on the PC and check that it reaches the
  iPhone with its alert. Add one on the iPhone and check that it appears in the
  card after a sync. Edit an iPhone event and keep its notes, and move it to
  another calendar. Edit and delete one occurrence of a repeating event, then
  the whole series.
