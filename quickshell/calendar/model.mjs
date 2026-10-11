// The calendar card's rules, free of QML and I/O so node can test them and the
// card can import them. Times are epoch seconds, read and built in local time
// (the card runs in the session's time zone). Names of days and months are not
// here: the views take them from Qt.locale(LC_TIME).

const pad = n => String(n).padStart(2, '0')
const local = s => new Date(s * 1000)

export function dayKey(s) {
    const d = local(s)
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate())
}
// dayStart("YYYY-MM-DD") — local midnight of that day, in seconds.
export function dayStart(key) {
    const [y, m, d] = key.split('-').map(Number)
    return Math.floor(new Date(y, m - 1, d).getTime() / 1000)
}
export function addDays(key, n) {
    const [y, m, d] = key.split('-').map(Number)
    return dayKey(Math.floor(new Date(y, m - 1, d + n).getTime() / 1000))
}
export function minutesOf(s) { const d = local(s); return d.getHours() * 60 + d.getMinutes() }
// at(key, minutes) — that local wall time on that day (DST-safe: built from parts).
export function at(key, minutes) {
    const [y, m, d] = key.split('-').map(Number)
    return Math.floor(new Date(y, m - 1, d, Math.floor(minutes / 60), minutes % 60).getTime() / 1000)
}
export function nextFullHour(now) {
    const d = local(now)
    d.setMinutes(0, 0, 0)
    d.setHours(d.getHours() + 1)
    return Math.floor(d.getTime() / 1000)
}
export function snapQuarter(minutes) { return Math.floor(minutes / 15) * 15 }

// parseTime("18" | "1830" | "18:30" | "18.30" | "6pm" | "6:30 pm") -> minutes, or null.
export function parseTime(text) {
    const m = String(text).trim().toLowerCase().match(/^(\d{1,2})(?:[:.]?(\d{2}))?\s*(am|pm)?$/)
    if (!m) return null
    let h = Number(m[1])
    const min = m[2] === undefined ? 0 : Number(m[2])
    if (min > 59) return null
    if (m[3]) {
        if (h < 1 || h > 12) return null
        h = h % 12 + (m[3] === 'pm' ? 12 : 0)
    } else if (h > 23) return null
    return h * 60 + min
}
export function formatTime(minutes, clock, am, pm) {
    const h = Math.floor(minutes / 60), min = minutes % 60
    if (clock !== '12h') return pad(h) + ':' + pad(min)
    return pad(h % 12 === 0 ? 12 : h % 12) + ':' + pad(min) + ' ' + (h < 12 ? am : pm)
}

export const DURATIONS = [15, 30, 60, 120]
export const ALERTS_TIMED = [
    { id: 'none', label: 'None' },
    { id: '0m', label: 'At time of event', trigger: 'PT0S' },
    { id: '5m', label: '5 minutes before', trigger: '-PT5M' },
    { id: '10m', label: '10 minutes before', trigger: '-PT10M' },
    { id: '15m', label: '15 minutes before', trigger: '-PT15M' },
    { id: '30m', label: '30 minutes before', trigger: '-PT30M' },
    { id: '1h', label: '1 hour before', trigger: '-PT1H' },
    { id: '2h', label: '2 hours before', trigger: '-PT2H' },
    { id: '1d', label: '1 day before', trigger: '-P1D' },
    { id: '2d', label: '2 days before', trigger: '-P2D' },
    { id: '1w', label: '1 week before', trigger: '-P1W' },
]
// All-day alerts are offsets from the day's midnight: 09:00 that day, or 09:00 N days before.
export const ALERTS_ALLDAY = [
    { id: 'none', label: 'None' },
    { id: 'day0', label: 'On the day (09:00)', trigger: 'PT9H' },
    { id: 'day1', label: '1 day before (09:00)', trigger: '-PT15H' },
    { id: 'day2', label: '2 days before (09:00)', trigger: '-P1DT15H' },
    { id: 'week', label: '1 week before (09:00)', trigger: '-P6DT15H' },
]
export function alertLabel(draft) {
    if (draft.alert === 'custom') return 'Custom (kept)'
    const list = draft.allDay ? ALERTS_ALLDAY : ALERTS_TIMED
    const found = list.find(x => x.id === draft.alert)
    return found ? found.label : 'None'
}
export function defaultAllDayAlert(timedId) { return timedId === 'none' ? 'none' : 'day0' }

// newDraft(now, {duration, alert, calendar}, [dayKey], [startMinutes])
export function newDraft(now, defaults, key, minutes) {
    const base = nextFullHour(now)
    const day = key || dayKey(base)
    const start = at(day, minutes === undefined || minutes === null ? minutesOf(base) : minutes)
    return {
        title: '', location: '', allDay: false,
        start: start, end: start + (defaults.duration || 60) * 60,
        startDay: day, endDay: day,
        calendar: defaults.calendar || '', alert: defaults.alert || '15m', timedAlert: defaults.alert || '15m',
    }
}
export function moveStart(d, start) {
    const length = d.end - d.start
    return Object.assign({}, d, { start: start, end: start + length, startDay: dayKey(start), endDay: dayKey(start + length) })
}
export function setEnd(d, end) { return Object.assign({}, d, { end: end, endDay: dayKey(end) }) }
export function setStartDay(d, key) {
    if (d.allDay) {
        const span = Math.round((dayStart(d.endDay) - dayStart(d.startDay)) / 86400)
        return Object.assign({}, d, { startDay: key, endDay: addDays(key, span) })
    }
    return moveStart(d, at(key, minutesOf(d.start)))
}
export function setEndDay(d, key) {
    if (d.allDay) return Object.assign({}, d, { endDay: key })
    return setEnd(d, at(key, minutesOf(d.end)))
}
export function setAllDay(d, on) {
    if (on === d.allDay) return d
    if (on) return Object.assign({}, d, { allDay: true, startDay: dayKey(d.start), endDay: dayKey(d.start),
        timedAlert: d.alert, alert: defaultAllDayAlert(d.alert) })
    const start = at(d.startDay, minutesOf(d.start)), end = start + (d.end - d.start)
    return Object.assign({}, d, { allDay: false, alert: d.timedAlert || '15m', start: start, end: end,
        startDay: dayKey(start), endDay: dayKey(end) })
}
// A new-event draft with a title is kept when the sheet is left by any route.
export function keepsDraft(d) { return !!d && d.mode !== 'edit' && !!String(d.title).trim() }
export function validate(d) {
    const endBeforeStart = d.allDay ? d.endDay < d.startDay : d.end <= d.start
    return { ok: !!String(d.title).trim() && !endBeforeStart, endBeforeStart: endBeforeStart }
}

// RFC 5545 text.
export function escapeText(s) {
    return String(s).replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\r?\n/g, '\\n')
}
const utf8Length = ch => { const c = ch.codePointAt(0); return c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4 }
// Folds at 75 octets, continuation lines start with one space; never splits a character.
export function foldIcsLine(line) {
    const out = []
    let cur = '', size = 0, limit = 75
    for (const ch of line) {
        const n = utf8Length(ch)
        if (size + n > limit) { out.push(cur); cur = ' '; size = 1; limit = 75 }
        cur += ch; size += n
    }
    out.push(cur)
    return out.join('\r\n')
}
const utc = s => { const d = local(s); return d.getUTCFullYear() + pad(d.getUTCMonth() + 1) + pad(d.getUTCDate())
    + 'T' + pad(d.getUTCHours()) + pad(d.getUTCMinutes()) + pad(d.getUTCSeconds()) + 'Z' }
const dateValue = key => key.replace(/-/g, '')

export function buildIcs(d, now, uid) {
    const lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//dotfiles//calendar card//EN', 'BEGIN:VEVENT',
        'UID:' + uid, 'DTSTAMP:' + utc(now)]
    if (d.allDay) {
        lines.push('DTSTART;VALUE=DATE:' + dateValue(d.startDay), 'DTEND;VALUE=DATE:' + dateValue(addDays(d.endDay, 1)))
    } else {
        lines.push('DTSTART:' + utc(d.start), 'DTEND:' + utc(d.end))
    }
    lines.push('SUMMARY:' + escapeText(d.title.trim()))
    if (String(d.location).trim()) lines.push('LOCATION:' + escapeText(d.location.trim()))
    const alert = (d.allDay ? ALERTS_ALLDAY : ALERTS_TIMED).find(x => x.id === d.alert)
    if (alert && alert.trigger) lines.push('BEGIN:VALARM', 'ACTION:DISPLAY', 'DESCRIPTION:' + escapeText(d.title.trim()),
        'TRIGGER:' + alert.trigger, 'END:VALARM')
    lines.push('END:VEVENT', 'END:VCALENDAR')
    return lines.map(foldIcsLine).join('\r\n') + '\r\n'
}
export function newUid(now) {
    return now.toString(36) + '-' + Math.random().toString(36).slice(2, 12) + '@calendar-card'
}

// ── Card state. Each bar segment owns a "home" view: the clock's is the month
// with Upcoming folded, the pill's the same with Upcoming unfolded. Clicking
// the segment whose home is showing closes; anything else goes to its home.
export const CLOSED = { open: false, unfolded: false, sheet: false, sheetReturn: null, day: null, year: false }
const home = unfolded => ({ open: true, unfolded: unfolded, sheet: false, sheetReturn: null, day: null, year: false })
const isHome = (s, unfolded) => s.open && !s.sheet && !s.day && !s.year && s.unfolded === unfolded
export function openSheet(s) { return Object.assign({}, s, { open: true, sheet: true, sheetReturn: s.open ? 'card' : 'close' }) }
export function transition(s, action) {
    switch (action) {
    case 'clock': return isHome(s, false) ? CLOSED : home(false)
    case 'pill': return isHome(s, true) ? CLOSED : home(true)
    case 'keybind': return s.open && s.sheet ? CLOSED : openSheet(s)
    case 'outside': return CLOSED
    case 'esc':
        if (!s.open) return s
        if (s.sheet) return s.sheetReturn === 'close' ? CLOSED : Object.assign({}, s, { sheet: false, sheetReturn: null })
        if (s.day) return Object.assign({}, s, { day: null })
        if (s.year) return Object.assign({}, s, { year: false })
        return CLOSED
    }
    return s
}

// monthGrid(year, monthIndex0, firstDayOfWeek 1=Mon..7=Sun) -> 42 cells.
export function monthGrid(year, month, firstDay) {
    const first = new Date(year, month, 1)
    const weekday = first.getDay() === 0 ? 7 : first.getDay()           // 1..7, Monday = 1
    const lead = (weekday - firstDay + 7) % 7
    const cells = []
    for (let i = 0; i < 42; i++) {
        const d = new Date(year, month, 1 - lead + i)
        cells.push({ key: dayKey(Math.floor(d.getTime() / 1000)), day: d.getDate(), inMonth: d.getMonth() === month })
    }
    return cells
}

// ── Upcoming: events not yet over, within 7 days of now.
function ahead(events, now, days) {
    const until = dayStart(addDays(dayKey(now), days))
    return events.filter(e => e.endEpoch > now && e.startEpoch < until).slice().sort((a, b) => a.startEpoch - b.startEpoch)
}
export function upcomingSummary(events, now) {
    const list = ahead(events, now, 7)
    return { next: list.length ? list[0] : null, more: Math.max(0, list.length - 1) }
}
export function groupUpcoming(events, now, days) {
    const groups = []
    for (const e of ahead(events, now, days || 7)) {
        const key = e.startEpoch < now ? dayKey(now) : dayKey(e.startEpoch)
        let g = groups.find(x => x.key === key)
        if (!g) { g = { key: key, events: [] }; groups.push(g) }
        g.events.push(e)
    }
    return groups
}

// ── Timeline of one day.
// Wall-clock hours since local midnight of `key` (may be <0 or >24); whole days come
// from calendar dates, so a 23 h or 25 h day still has 24 hours on the strip.
const dayNumber = key => { const [y, m, d] = key.split('-').map(Number); return Date.UTC(y, m - 1, d) / 86400000 }
const hourOf = (s, key) => (dayNumber(dayKey(s)) - dayNumber(key)) * 24 + minutesOf(s) / 60
export function timelineRange(events, draft, key) {
    let from = 8, to = 22
    const timed = events.filter(e => !e.allDay)
    if (draft && !draft.allDay) timed.push({ startEpoch: draft.start, endEpoch: draft.end })
    for (const e of timed) {
        from = Math.min(from, Math.floor(Math.max(0, hourOf(e.startEpoch, key))))
        to = Math.max(to, Math.ceil(Math.min(24, hourOf(e.endEpoch, key))))
    }
    return { from: Math.max(0, from), to: Math.min(24, to) }
}
export function ticks(from, to) {
    const out = []
    for (let h = from; h < to; h += 4) if (to - h > 1 || h === from) out.push(h)
    if (out[out.length - 1] !== to) out.push(to)
    return out
}
// Lane 0 unless it overlaps an earlier event in lane 0; everything else shares lane 1.
export function lanes(events) {
    const sorted = events.slice().sort((a, b) => a.startEpoch - b.startEpoch)
    let lane0End = -Infinity
    return sorted.map(e => {
        if (e.startEpoch >= lane0End) { lane0End = e.endEpoch; return Object.assign({}, e, { lane: 0 }) }
        return Object.assign({}, e, { lane: 1 })
    })
}
export function clashes(draft, events) {
    if (!draft || draft.allDay) return []
    const self = e => draft.uid && e.uid === draft.uid && e.startEpoch === draft.occurrence
    return events.filter(e => !e.allDay && !self(e) && e.startEpoch < draft.end && e.endEpoch > draft.start)
}
// ── Editing. A draft built from a listed event and what `cal.sh inspect` found.
export function draftFromEvent(e, info, defaults) {
    return {
        title: e.title, location: e.location || '', allDay: !!e.allDay,
        start: e.startEpoch, end: e.endEpoch,
        startDay: dayKey(e.startEpoch), endDay: e.allDay ? dayKey(e.endEpoch - 1) : dayKey(e.endEpoch),
        calendar: e.calendar, alert: info.alert, timedAlert: e.allDay ? (defaults.alert || '15m') : info.alert,
        mode: 'edit', uid: e.uid, occurrence: e.startEpoch, recurring: !!info.recurring,
        readOnly: !!info.readOnly, invitation: !!info.invitation, originalCalendar: e.calendar,
        hash: info.hash, hadCustom: info.alert === 'custom',
    }
}
export function changesOf(d) {
    return { title: d.title.trim(), location: String(d.location).trim(), allDay: d.allDay, start: d.start, end: d.end,
        startDay: d.startDay, endDay: d.endDay, alert: d.alert }
}
// The scopes a save offers: none for a one-off; a calendar change moves the whole series.
export function scopeChoices(d) {
    if (!d.recurring) return []
    return d.calendar !== d.originalCalendar ? ['all'] : ['one', 'all']
}
export function alertItems(d) {
    const list = (d.allDay ? ALERTS_ALLDAY : ALERTS_TIMED).slice()
    if (d.hadCustom) list.push({ id: 'custom', label: 'Custom (kept)' })
    return list
}

// segment(event, key, range) -> {left, width} as fractions of the strip, and cut
// when it runs past the strip's end.
export function segment(e, key, range) {
    const span = range.to - range.from
    const a = Math.max(range.from, hourOf(e.startEpoch, key)), b = Math.min(range.to, hourOf(e.endEpoch, key))
    return { left: (a - range.from) / span, width: Math.max(0, b - a) / span, cut: hourOf(e.endEpoch, key) > range.to }
}
// The minutes a click at fraction x of the strip means, snapped to the quarter hour.
export function minutesAt(x, range) { return snapQuarter(Math.round((range.from + x * (range.to - range.from)) * 60)) }
