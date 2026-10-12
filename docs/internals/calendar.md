# Calendar

Moved verbatim from `CLAUDE.md` so the agent instructions stay short. `CLAUDE.md` keeps the rules that must hold on every edit; this file has the reasoning and the traps.

`scripts/calendar/sync.sh` is the normal path to iCloud: a `flock`, then
`vdirsyncer metasync` and `sync` into `~/.local/share/calendars/icloud/`, a daily
discover, `writable.sh` and `declined.py`, then `agenda.json` and `status.json`
in `$XDG_RUNTIME_DIR/calendar/` and signal 12. A failed render is a failed sync,
and `sync.sh --render` exits 1 so the panel can roll back. `cal.sh` add, update
and delete take the same `sync.lock` (or are refused), and `setup.sh --sign-out`
stops the service and takes that lock before clearing anything.
`setup.sh --sign-in` is the exception: it runs discover and `writable.sh` outside
that lock, and `writable.sh`'s PROPFINDs use `curl` directly. `sync.sh --render` does no network.
`cal.sh` is the only khal reader and writer; `khal/config` holds the ISO formats
it parses, and everything shown is localised from `LC_TIME`. Adds go through
`khal import --batch -a`, never `khal new`, which splits the summary on ` :: `.
Passwords live only in the keyring and reach vdirsyncer, `curl -K -` and
`secret-tool store` on stdin, never in argv. `secret-tool lookup` exits 1 with no
output for a missing item, and anything else means the keyring could not be read.
`agenda-bar.sh` reads only `agenda.json` and the options. `model.mjs` holds the
card's transition table, and the card is centred on the monitor, not the capsule. Edits
go through `ics-edit.py`: the event's own TZID, overrides and EXDATEs, the hash
check and an atomic rename, since vdirsyncer notices a new inode. iCloud colours
arrive as `#RRGGBBAA` and are cut to `#RRGGBB`, because Qt reads eight digits as
ARGB. The iCloud Reminders list is a VTODO-only collection, so `writable.sh`
records it in `skip`. Read-only calendars come from the PROPFIND probe. iCloud
writes ORGANIZER as a principal path with `EMAIL=`, so addresses are normalised
the same way in `addresses`, `declined.py` and `ics-edit.py`. Declined invitations
are hidden through the `declined` rules in `cal.sh list()`, unless `options/calendar-declined` says `enabled`. khal 0.14.1 exits 2
on an unknown or duplicated `-d` name, and excluding every calendar means no
filter. `sync.sh` matches 401 only as a whole word, because UUID collection names
contain digit runs. `options/calendar-*` is untracked because calendar names are
personal. The card runs `cal.sh` directly, so it must stay mode 100755. Its
FileViews use `blockAllReads`, and its month, year and day readers queue per key.
See `docs/calendar.md`.
