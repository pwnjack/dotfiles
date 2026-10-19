# Update card (Waybar custom/updates)

Clicking the bar's updates module opens a small Quickshell card under it:
`scripts/hyprland/updates-popover.sh` toggles `quickshell/updates/shell.qml`,
anchored to the cursor's x on the bar's edge, and the process exits when the
card closes. The update itself is a separate detached run that the card only
starts and watches. The card's colours come from the matugen palette (the
launcher passes the background, the readable foreground and the `primary` role
as the accent); `palette.sh`'s fallback palette stands in when none has been
generated.

## What it does

- **Summary.** `scripts/updates/updates-plan.sh` lists what is pending: repo
  packages with their size, AUR packages, and whether the running kernel is
  replaced. The package list is collapsed until you open it. A failed check is
  shown as "Could not check for updates", never as "Up to date". While the
  check runs, the header badge's glyph gives way to a spinner.
- **The last check is reused.** Every plan the planner prints, from the card or
  the bar's half-hourly check, is also saved as
  `$XDG_RUNTIME_DIR/updates/plan.json`. The card opens on that saved plan
  (`updates-plan.sh --cached`). If it is under ten minutes old, the card does
  not check again, so closing it by mistake and reopening costs nothing. If it
  is older, the card shows it straight away and checks again behind it: the
  spinner turns, the clock line beside the buttons says "Checking…", and the
  new plan replaces it when it arrives. Otherwise that line says how old the
  plan is ("4 min ago"). A saved plan is not used once pacman's local
  database or a Flatpak installation (its `.changed` marker) has changed since
  its check began (any install or upgrade, from the card, a terminal or
  anywhere else), nor after a check found the upgrade unresolvable. A stale list cannot install the wrong thing: Update runs the
  root helper's own `pacman -Syu`.
- **Update** starts `scripts/updates/updates-run.sh` under `setsid`. The card
  then shows a progress bar and pacman's current step. Closing the card (Esc,
  a click outside) does not stop the update; reopening it resumes at the
  current percentage.
- **Result.** Done closes the card by itself after about 3 s. Restart (a new
  kernel is installed), failed and attention (amber, with pacman's reason)
  stay until dismissed, with a button for the terminal path that fits.
  Activation keys are ignored for about a second after any view appears, so an
  accidental Return can never start an update or a reboot.
- **The bar** follows the same state: a running class while the update runs,
  and a restart or attention class that stays until the card has shown the
  result (`ack`, below). Its count is the planner's (`repo + AUR + Flatpak`),
  so it equals the card's. Hovering shows a summary built by
  `model.tooltip()` (printed by `scripts/updates/tooltip.mjs`): a row per
  non-zero source, the download size, a kernel line, and when it last
  checked. While running it shows pacman's step, and after a run the card's
  result copy. If node fails, a one-line tooltip stands in.
- **AUR and Flatpak-only updates run in a terminal.** The card says how many there are and
  offers the terminal (`scripts/updates/terminal.sh aur|pacman|flatpak`, which
  opens `options/terminal`). Every pending mix has a path: Update runs repo
  packages and then Flatpak, the AUR link (`terminal.sh aur`, which runs
  `scripts/settings/update.sh`) runs the AUR helper and then Flatpak, and Flatpak updates on their own get the same link to
  `terminal.sh flatpak`. Without repo packages the subtitle says "Runs in a
  terminal", because the plan's download size covers repo packages only.

## Setting it up

```bash
bash ~/.config/updates/setup-sudo.sh
```

Run it in your own terminal; it asks for your sudo password itself. It
installs `updates/system-update-root.sh` as the root-owned
`/usr/local/bin/system-update` and writes `/etc/sudoers.d/system-update`. It is
idempotent and verifies the NOPASSWD entry by reading `sudo -n -l`, without
running the update.

**Re-run it only after reviewing `updates/system-update-root.sh`.** Setup
copies that user-writable file to a path that runs as root, so anything able to
change the source gains root the next time setup is run. The installed copy is
what runs between setups.

Until the grant exists the card says "One-click updates are not set up" and
offers a terminal update. `sudo -l` lists the empty-argument rule as
`/usr/local/bin/system-update ""`, and the setup script checks for exactly that
spelling.

## Privilege model

- One sudoers rule: `NOPASSWD: /usr/local/bin/system-update ""`. The trailing
  `""` pins an empty argument list, and the helper itself refuses any
  argument. It takes no input at all: `PATH` and the locale are set inside, and
  `#!/bin/bash -p` ignores imported functions and `BASH_ENV`.
- What it can do is bounded by root-owned files: `pacman.conf`, the keyring and
  repo signatures. The most a user-level caller gains is an upgrade to
  correctly signed repo packages. It never runs paru, flatpak or anything
  else, and never reboots.
- The card's Update button is an accident guard, not a security boundary.
- **polkit was rejected.** Only one agent may register per session, and
  hyprpolkitagent's dialog cannot be styled, so an authentication prompt would
  break the card's look and flow. (Flatpak needs nothing:
  `org.freedesktop.Flatpak.app-update` is `implicit active: yes`.)
- **AUR stays in the terminal.** paru runs `sudo pacman -U <file>` on a
  freshly built package; that cannot be passwordless without a rule for
  arbitrary files, and PKGBUILD review belongs in front of a person.

## How a run flows

```
card Update -> updates-run.sh (setsid, holds run.lock)
   sudo -n /usr/local/bin/system-update   pacman -Syuw, then pacman -Su
   flatpak update --noninteractive -y     only if pacman succeeded
   | tee -p -a run.log | node fold.mjs state.json   (model.mjs)
-> $XDG_RUNTIME_DIR/updates/state.json -> card (polls 120 ms) and bar
```

The helper's markers, folded unprivileged (keep the root file small):

| Marker | Meaning |
|---|---|
| `@@phase download` / `install` | before `pacman -Syuw` / `pacman -Su`; `download` is informational, the model enters the download phase from pacman's `:: Retrieving packages` line |
| `@@bytes <n>` | every 0.5 s while downloading: bytes added to the cache |
| `@@busy` | another update holds `/run/system-update.lock` (exit 75) |

The runner adds `@@helper-exit <n>`, `@@phase flatpak`, `@@flatpak-exit <n>`,
`@@restart <kernel>` and `@@end`.

`state.json` is `model.snapshot()`: `status` (`running`, `done`, `restart`,
`failed`, `attention`), `phase`, `key`, `line`, `progress` (0–1), `done`,
`total`, `bytes`, `totalBytes`, `error`, `detail`, `errorKind` (`''` while
running or on success, `pacman`, `transaction`, `busy`, `sudo`, `flatpak`,
`unknown`), `restart` (the kernel to boot), `nothing`,
`startedAt`, `finishedAt`. `fold.mjs` replaces the file by rename and signals
Waybar. `ack` sits beside it and holds the `finishedAt` of the last result the
card showed; the bar keeps an unseen restart or attention class until
`ack == finishedAt`.

- **Restart is derived, not listed.** Replacing the running kernel removes
  `/usr/lib/modules/$(uname -r)`, so its absence after a successful run is the
  signal; no package names appear anywhere. The restart names the newest
  kernel of the running flavour (`-cachyos` vs `-cachyos-lts`). A pending
  restart outranks a Flatpak failure.
- **Readers trust `run.lock` over `state.json`.** Running with a free lock is
  stale; a held lock with no state is running at 0 %. The card probes it
  read-only through `/proc/locks`.
- **A run never depends on the fold.** `tee -p` keeps `run.log` and the helper
  alive if `fold.mjs` dies; afterwards an unfinished fold is redone from the
  complete `run.log`, then replaced by a terminal snapshot, so `running` is
  never left behind. The runner clears `state.json` under its lock when it
  starts, so the card never shows the previous result.
- **The helper is hard to damage.** Terminating it is deferred until the
  foreground pacman returns, so a transaction is never interrupted; the byte
  sampler and the lock go with it; pacman runs with the lock fd closed.

## Traps

- **No terminal, no counters.** Without a tty pacman 7.1 prints one plain line
  per step (`checking keyring...`, `upgrading 7zip...`), with no counters or
  bars. The package total comes from the `Packages (N)` header, and
  `VerbosePkgLists` changes it to `Package (N)  Old Version …` plus a table;
  the model accepts both.
- **`LC_ALL=C` everywhere pacman is parsed.** A comma-decimal locale (such as
  `it_IT`) prints `6,48 MiB`.
- **`stdbuf -oL -eL`.** pacman block-buffers stdout into a pipe, which would
  deliver a whole phase's lines at once and make the bar jump.
- **DownloadUser.** `DownloadUser = alpm` downloads into a `download-XXXXXX`
  directory inside the cache, then moves finished files up. Cache growth
  counts the whole directory, so every byte is counted once.
- **`--noconfirm` answers No to conflicts**, so pacman aborts before changing
  anything. The card says "The update stopped before changing anything" and
  offers the terminal.
- **Mirror noise is not failure.** libalpm's `error: failed retrieving file …
  from <mirror>` is non-fatal; the model ignores it and keeps the last one
  only as a fallback reason if the download really fails. `::` dependency
  explanations are kept as the reason; `warning:` lines are skipped.
- **checkupdates and paru exit codes.** `checkupdates` exits 2 for "no
  updates" and `paru -Qua` is unreliable. The plan accepts checkupdates only as
  0 or 2 and ignores the AUR helper's and Flatpak's status. The plan itself
  exits 1 when the check failed (the bar hides) and 3 when `pacman -Sup`
  cannot resolve the upgrade (the bar shows its glyph with "Updates need a
  terminal"); the card shows either as an error. Both run the planner, so they
  share the private `CHECKUPDATES_DB` through the planner's `flock`, and
  `pacman -Sup --dbpath <that dir> --print-format '%n %s %l'` works without
  root.
- **QML.** Qt's V4 engine rejects object spread in `.mjs` imported by QML
  (`model.mjs` uses `Object.assign`), and a QML property named `on<Name>` is
  parsed as a signal handler (hence `accentInk`/`warnInk`).
- **Glyphs** are written as escapes (`String.fromCodePoint(0xf06b0)`,
  `$'\U000f06b0'`); retyped private-use characters silently vanish.
- `*.log` is gitignored, so the test fixtures are negated in `.gitignore`.

## Checks

- `bash quickshell/updates/test/run-tests.sh` (model under node, then the
  offscreen view under `qmltestrunner`)
- `bash scripts/updates/test/test-run.sh` (runner and fold)
- `bash scripts/updates/test/test-plan.sh` (the plan)
- `bash scripts/waybar/test-updates.sh` (the bar module)
- `qs -p ~/.config/quickshell/updates/shell.qml ipc call updates status`
  while open answers JSON including `mode`.

Replaying a run without root: write a helper in `$XDG_RUNTIME_DIR` that prints
`quickshell/updates/test/fixtures/routine.log` line by line with `sleep 0.3`,
stopping before its `@@helper-exit` line (the runner adds its own markers).
Then, in one shell:

```bash
export UPDATES_STATE_DIR=$XDG_RUNTIME_DIR/updates-demo UPDATES_SUDO=none \
       UPDATES_SIGNAL=none UPDATES_FLATPAK=/nonexistent \
       UPDATES_HELPER=$XDG_RUNTIME_DIR/updates-demo-helper.sh
scripts/updates/updates-run.sh &
scripts/hyprland/updates-popover.sh
```

`UPDATES_FLATPAK=/nonexistent` keeps a demo from running a real Flatpak
update. Use `conflict.log` for the amber attention state and `kernel.log` with
`UPDATES_MODULES_DIR` pointing at a temp dir lacking the running kernel for
restart. Drive the card through the launcher and IPC only, never synthetic
input, and remove the demo state dir, the helper and the exports afterwards.
