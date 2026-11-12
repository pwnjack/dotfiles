# Calendar

Contract (behaviour, data path, errors and files: [calendar.md](../calendar.md)):

- `scripts/calendar/sync.sh` is the normal path to iCloud, under `sync.lock`; `sync.sh --render` does no network and exits 1 on a failed render so the panel can roll back. `cal.sh` add, update and delete take the same lock (or are refused), and `setup.sh --sign-out` takes it before clearing anything. `setup.sh --sign-in` is the exception, and `writable.sh`'s PROPFINDs use `curl` directly. [How it works](../calendar.md#how-it-works), [Setup](../calendar.md#setup).
- `cal.sh` is the only khal reader and writer; `khal/config` holds the ISO formats it parses, and everything shown is localised from `LC_TIME`. Adds go through `khal import --batch -a`, never `khal new`, which splits the summary on ` :: `. [The new-event sheet](../calendar.md#the-new-event-sheet).
- Edits go through `ics-edit.py` (own TZID, overrides and EXDATEs, the hash check, an atomic rename, since vdirsyncer notices a new inode). The edit draft takes its title and location from `inspect`, the read its hash covers, and the sheet locks its fields while a write waits on `sync.lock`. [Editing and deleting](../calendar.md#editing-and-deleting).
- `agenda-bar.sh` reads only `agenda.json` and the options. [The bar capsule](../calendar.md#the-bar-capsule).
- `model.mjs` holds the card's transition table; the card is centred on the monitor, not the capsule. [The card](../calendar.md#the-card).
- Passwords live only in the keyring and reach vdirsyncer, `curl -K -` and `secret-tool store` on stdin, never in argv. `secret-tool lookup` exits 1 with no output for a missing item, and anything else means the keyring could not be read.
- iCloud writes ORGANIZER as a principal path with `EMAIL=`, so addresses are normalised the same way in `addresses`, `declined.py` and `ics-edit.py`. Declined invitations are hidden through the `declined` rules in `cal.sh list()`, unless `options/calendar-declined` says `enabled`. [Editing and deleting](../calendar.md#editing-and-deleting).
- iCloud colours arrive as `#RRGGBBAA` and are cut to `#RRGGBB` (Qt reads eight digits as ARGB); the Reminders list is VTODO-only, so `writable.sh` records it in `skip`; read-only calendars come from the PROPFIND probe. [How it works](../calendar.md#how-it-works).
- khal 0.14.1 exits 2 on an unknown or duplicated `-d` name, and excluding every calendar means no filter.
- `sync.sh` matches 401 only as a whole word, because UUID collection names contain digit runs.
- `options/calendar-*` is untracked because calendar names are personal.
- The card runs `cal.sh` directly, so it must stay mode 100755. Its FileViews use `blockAllReads`, and its month, year and day readers queue per key.
