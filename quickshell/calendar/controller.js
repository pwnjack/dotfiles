.pragma library

// The card's controller logic. shell.qml runs it against the real controller,
// and tst_Card.qml runs the same functions against a fake controller and a text
// draft writer, so a test of this file tests the shell's path too.
//
// Every function takes the model module M (a .js file cannot import a .mjs), the
// controller c, and, where it writes the draft, a writer w with setText(text).
// Nothing here names a QML type.

// Navigation retires every cal.sh reply still in flight: a reply asked before
// it may no longer open a sheet or close one. Also clears the card's error line.
function invalidate(c) {
    c.sheetSession += 1;
    c.addError = "";
}

// A typed new-event draft is written to draft.json; an edit or a blank title is not.
function keepDraft(M, c, w) {
    const text = M.draftToKeep(c.draft);
    if (text !== null) w.setText(text);
}

// A click on a listed event: a typed new-event draft is kept first, then
// start(session) asks cal.sh inspect. Its reply comes back to inspectReply
// with that same session.
function beginEdit(M, c, w, e, start) {
    keepDraft(M, c, w);
    start(c.sheetSession);
}

// cal.sh inspect's reply. Returns "opened", "failed" or "dropped". An inspect is a
// read: once navigation has retired the session that asked, its reply is dropped
// whether it succeeded or failed, so an abandoned read never leaves an error behind.
function inspectReply(M, c, asked, e, info) {
    if (asked !== c.sheetSession) return "dropped";
    const ok = !!info && info.ok !== false;
    if (!ok) {
        c.addError = info && info.error ? info.error : "The event could not be read.";
        return "failed";
    }
    const writable = c.calendars.some(x => x.name === e.calendar && x.writable);
    c.draft = M.draftFromEvent(e, Object.assign({}, info, { readOnly: !writable || info.invitation }), c.defaults());
    c.addError = "";
    c.state = M.openSheet(c.state);
    c.loadDay(c.draft.startDay);
    return "opened";
}

// cal.sh update|delete's reply. A saved change always highlights its event; only
// the sheet that asked may close or clear its draft.
function updateReply(M, c, asked, title, r) {
    const ok = !!r.ok;
    const verdict = M.replyVerdict(asked, c.sheetSession, ok, c.state.sheet);
    if (ok) {
        if (verdict === "apply") { c.draft = null; c.act("esc"); }
        c.flash(title);
    } else if (verdict !== "drop") {
        c.addError = r.error || "The change could not be saved.";
    }
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

// The calendar list from cal.sh calendars. A failed run prints {"ok":false,…}, which
// is not a list: the list shown stays. An empty list is a real answer. A draft that
// names a calendar no longer writable takes the default (a new event) or turns
// read-only (an edit, whose calendar is gone or whose event is an invitation).
function calendarsReply(M, c, list) {
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
