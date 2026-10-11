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

// cal.sh inspect's reply. Returns "opened", "failed" or "dropped".
function inspectReply(M, c, asked, e, info) {
    const ok = !!info && info.ok !== false;
    const verdict = M.replyVerdict(asked, c.sheetSession, ok, c.state.sheet);
    if (!ok) {
        if (verdict === "drop") return "dropped";
        c.addError = info && info.error ? info.error : "The event could not be read.";
        return "failed";
    }
    if (verdict !== "apply") return "dropped";
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
