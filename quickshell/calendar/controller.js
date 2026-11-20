.pragma library

// The card's controller logic. shell.qml runs it against the real controller,
// and tst_Card.qml runs the same functions against a fake controller and a text
// draft writer, so a test of this file tests the shell's path too.
//
// Each function takes only what it uses, in this order: the model module M (a .js
// file cannot import a .mjs), the controller c and a draft writer w (setText).
// Nothing here names a QML type.

// Navigation retires every cal.sh reply still in flight: a reply asked before
// it may no longer open a sheet or close one. Also clears the card's error line.
function invalidate(c) {
    c.sheetSession += 1;
    c.addError = "";
}

// A click on a month day selects it, and a second click on the selected day closes
// it again, as the day header's × does; the month stays where it is either way.
// Returns true when a day was selected, so the caller loads its events.
function selectDay(c, key) {
    if (key === c.state.day) { closeDay(c); return false; }
    c.state = Object.assign({}, c.state, { day: key, year: false });
    return true;
}
function closeDay(c) { c.state = Object.assign({}, c.state, { day: null }); }

// A typed new-event draft is written to draft.json; an edit or a blank title is not.
function keepDraft(M, c, w) {
    const text = M.draftToKeep(c.draft);
    if (text !== null) w.setText(text);
}

// A click on a listed event: a typed new-event draft is kept first, then
// start(session) asks cal.sh inspect. Its reply comes back to inspectReply
// with that same session.
function beginEdit(M, c, w, start) {
    keepDraft(M, c, w);
    start(c.sheetSession);
}

// cal.sh inspect's reply: it opens the sheet or sets the error line. An inspect is a
// read: once navigation has retired the session that asked, its reply is dropped
// whether it succeeded or failed, so an abandoned read never leaves an error behind.
function inspectReply(M, c, asked, e, info) {
    if (asked !== c.sheetSession) return;
    const ok = !!info && info.ok !== false;
    if (!ok) {
        c.addError = info && info.error ? info.error : "The event could not be read.";
        return;
    }
    const writable = c.calendars.some(x => x.name === e.calendar && x.writable);
    c.draft = M.draftFromEvent(e, Object.assign({}, info, { readOnly: !writable || info.invitation }), c.defaults());
    c.addError = "";
    c.state = M.openSheet(c.state);
    c.loadDay(c.draft.startDay);
}

// cal.sh update|delete's reply. A saved change always highlights its event; only
// the sheet that asked may close or clear its draft. A failure is reported as an
// add's is: on the sheet, or to the desktop once nothing on the card shows it.
function updateReply(M, c, asked, title, r) {
    const ok = !!r.ok;
    const verdict = M.replyVerdict(asked, c.sheetSession, ok, c.state.sheet);
    if (ok) {
        if (verdict === "apply") { c.draft = null; c.act("esc"); }
        c.flash(title);
        return;
    }
    const message = r.error || "The change could not be saved.";
    if (verdict === "apply" || verdict === "card") c.addError = message;
    if (verdict === "drop" || !c.state.open) c.notifyFailure(message);
}

// cal.sh add's reply. Like an update, only the sheet that asked may close or clear
// its draft. A stale success still saved its event, so only the kept copy of that
// draft goes (it would reopen the event). `sent` is the draft JSON the request was
// made from, `w` the draft file. A failure nobody can see now goes to the desktop.
function addReply(M, c, asked, sent, title, r, w) {
    const verdict = M.replyVerdict(asked, c.sheetSession, !!r.ok, c.state.sheet);
    if (!r.ok) {
        const message = r.error || "The event could not be saved.";
        if (verdict === "apply" || verdict === "card") c.addError = message;
        if (verdict === "drop" || !c.state.open) c.notifyFailure(message);
        return;
    }
    if (verdict === "apply" && !!c.draft && JSON.stringify(c.draft) === sent) {
        w.setText("");
        c.draft = null;
        c.flash(title);
        c.act("esc");
        return;
    }
    if (w.text() === sent) w.setText("");
    c.flash(title);
}

// Writes in flight. A dismissed card quits only after every write has answered, so
// no reply is lost with the window. A count, not a flag: two writes can overlap (an
// add still running while an event is saved), and the first reply must not quit.
function beginWrite(c) { c.pendingWrites += 1; }
function endWrite(c) {
    c.pendingWrites = Math.max(0, c.pendingWrites - 1);
    if (c.quitting && c.pendingWrites === 0) c.quit();
}
// The card was dismissed: quit now, or when the last write answers.
function dismissed(c) {
    if (!c.closing) return;
    c.quitting = true;
    if (c.pendingWrites === 0) c.quit();
}
// A reopened card stays up: a quit still waiting on a write is cancelled.
function reopened(c) { c.quitting = false; }

// The calendar list from cal.sh calendars. A failed run prints {"ok":false,…}, which
// is not a list: the list shown stays. An empty list is a real answer. A draft that
// names a calendar no longer writable takes the default (a new event) or turns
// read-only (an edit, whose calendar is gone or whose event is an invitation).
function calendarsReply(c, list) {
    if (!Array.isArray(list)) return;
    c.calendars = list;
    const d = c.draft;
    if (!d) return;
    const writable = name => list.some(x => x.name === name && x.writable);
    if (d.mode === "edit") {
        const readOnly = !writable(d.originalCalendar) || !!d.invitation;
        if (readOnly !== !!d.readOnly) c.draft = Object.assign({}, d, { readOnly: readOnly });
    } else if (!writable(d.calendar)) {
        c.draft = Object.assign({}, d, { calendar: c.defaults().calendar });
    }
}

// The card header's sync line. The settings panel words the account its own way.
function headerStatus(M, c) {
    const status = c.status;
    if (!c.syncGaveUp && (!status || (status.lastAttempt || 0) < c.openedAt - 1)) return "syncing…";
    if (!status || status.state === "none") return "Not signed in";
    if (status.state === "failed") {
        if (status.kind === "auth") return "Sign-in rejected · Fix in Settings";
        const t = status.lastSuccess ? M.formatTime(M.minutesOf(status.lastSuccess), c.clock, c.locale.amText, c.locale.pmText) : "";
        return status.kind === "network" ? (t ? "Offline · showing events from " + t : "Offline") : status.message;
    }
    const ago = Math.round((c.now - (status.lastSuccess || c.now)) / 60);
    return "iCloud · " + (ago <= 0 ? "synced just now" : "synced " + ago + " min ago");
}

// The month and year arrows. Each one moves the view, so it retires pending replies.
function shiftMonth(c, delta) {
    const d = new Date(c.viewYear, c.viewMonth + delta, 1);
    c.viewYear = d.getFullYear();
    c.viewMonth = d.getMonth();
    invalidate(c);
    c.loadMonth();
}
function shiftYear(c, delta) {
    c.viewYear += delta;
    invalidate(c);
    c.loadYear();
}

// The helpers print {"ok":false,"error":…} on failure: any other shape reads as
// empty rather than throwing.
function asArray(value) { return Array.isArray(value) ? value : []; }
function parseJson(body) { try { return JSON.parse(body); } catch (e) { return null; } }
function parseBusy(body) { const r = parseJson(body); return r && Array.isArray(r.busy) ? r.busy : []; }
function parseCounts(body) { const r = parseJson(body); return r && Array.isArray(r.counts) && r.counts.length === 12 ? r.counts : []; }

// A reader (shell.qml's Process with verb and queued) runs one cal.sh verb at a
// time. The request's key is echoed on the first output line, so a result is
// stored under the key it was asked for, whatever was requested while it ran;
// the newest request runs when it ends.
function startReader(c, reader, key) {
    if (reader.running) { reader.queued = key; return; }
    reader.queued = "";
    reader.command = ["bash", "-c", 'printf "%s\\n" "$2"; "$1" "$3" "$2"', "bash", c.calSh, key, reader.verb];
    reader.running = true;
}
function readerDone(c, verb, text) {
    const cut = text.indexOf("\n");
    if (cut < 0) return;
    const key = text.slice(0, cut), body = text.slice(cut + 1);
    if (verb === "month") { const b = Object.assign({}, c.busy); b[key] = parseBusy(body); c.busy = b; }
    else if (verb === "year") { const n = Object.assign({}, c.counts); n[key] = parseCounts(body); c.counts = n; }
    else if (verb === "peek") { if (key === c.peekFor) c.peekEvents = asArray(parseJson(body)); }   // only the newest hover's day is kept
    else if (key === c.state.day || (c.state.sheet && c.draft && key === c.draft.startDay)) { c.dayEvents = asArray(parseJson(body)); c.dayFor = key; }   // a day neither view shows is dropped
}
