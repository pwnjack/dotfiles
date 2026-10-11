import assert from 'node:assert/strict'
import * as M from '../model.mjs'

process.env.TZ = 'Europe/Rome'
const at = (s) => Math.floor(new Date(s).getTime() / 1000)   // local "YYYY-MM-DDTHH:MM"

// Times
for (const [text, minutes] of [['18', 1080], ['1830', 1110], ['18:30', 1110], ['18.30', 1110], ['6pm', 1080],
    ['6:30 pm', 1110], ['12am', 0], ['12pm', 720], [' 9 ', 540]]) assert.equal(M.parseTime(text), minutes, text)
for (const text of ['25', '18:61', 'abc', '', '13pm']) assert.equal(M.parseTime(text), null, text)
assert.equal(M.formatTime(1110, '24h'), '18:30')
assert.equal(M.formatTime(1110, '12h', 'AM', 'PM'), '06:30 PM')
assert.equal(M.formatTime(0, '12h', 'AM', 'PM'), '12:00 AM')

// Day keys and the next full hour
assert.equal(M.dayKey(at('2026-10-11T16:52')), '2026-10-11')
assert.equal(M.nextFullHour(at('2026-10-11T16:52')), at('2026-10-11T17:00'))
assert.equal(M.nextFullHour(at('2026-10-11T23:10')), at('2026-10-12T00:00'))

// Drafts
const defaults = { duration: 60, alert: '15m', calendar: 'Home' }
let d = M.newDraft(at('2026-10-11T16:52'), defaults)
assert.equal(d.start, at('2026-10-11T17:00'))
assert.equal(d.end, at('2026-10-11T18:00'))
assert.equal(d.alert, '15m')
assert.equal(d.calendar, 'Home')
assert.deepEqual(M.validate(d), { ok: false, endBeforeStart: false })   // no title yet
d = Object.assign({}, d, { title: 'Dentist' })
assert.equal(M.validate(d).ok, true)
d = M.moveStart(d, at('2026-10-13T20:30'))
assert.equal(d.end, at('2026-10-13T21:30'))
d = M.setEnd(d, at('2026-10-13T20:00'))
assert.deepEqual(M.validate(d), { ok: false, endBeforeStart: true })
d = M.setEnd(d, at('2026-10-13T22:00'))
assert.equal(M.moveStart(d, at('2026-10-14T09:00')).end, at('2026-10-14T10:30'))   // keeps 90 min
const onDay = M.newDraft(at('2026-10-11T16:52'), defaults, '2026-10-17')
assert.equal(onDay.start, at('2026-10-17T17:00'))                                 // the chosen day, next-hour time
const atGap = M.newDraft(at('2026-10-11T16:52'), defaults, '2026-10-13', 20 * 60 + 15)
assert.equal(atGap.start, at('2026-10-13T20:15'))
assert.equal(M.snapQuarter(20 * 60 + 22), 20 * 60 + 15)

// All day
let a = M.setAllDay(Object.assign({}, onDay, { title: 'Birthday' }), true)
assert.equal(a.allDay, true)
assert.equal(a.startDay, '2026-10-17')
assert.equal(a.endDay, '2026-10-17')
assert.equal(a.alert, 'day0')
assert.equal(M.setAllDay(Object.assign({}, onDay, { alert: 'none' }), true).alert, 'none')
assert.equal(M.validate(M.setEndDay(a, '2026-10-16')).endBeforeStart, true)
{   // turning all day off keeps the day chosen meanwhile, and the timed length
    const moved = M.setStartDay(a, '2026-10-20')
    const back = M.setAllDay(moved, false)
    assert.equal(back.startDay, '2026-10-20')
    assert.equal(back.start, at('2026-10-20T' + new Date(onDay.start * 1000).toTimeString().slice(0, 5)))
    assert.equal(back.end - back.start, onDay.end - onDay.start)
    assert.equal(back.endDay, M.dayKey(back.end))
}
assert.equal(M.defaultAllDayAlert('none'), 'none')
assert.equal(M.defaultAllDayAlert('30m'), 'day0')

// ICS: timed
const t = Object.assign(M.newDraft(at('2026-10-11T16:52'), defaults, '2026-10-13', 20 * 60 + 30),
    { title: 'Riunione :: budget, Q4; R&D\\ok', location: 'Sala 2\nPiano 1' })
const ics = M.buildIcs(t, at('2026-10-11T16:52'), 'uid-1')
assert.ok(ics.startsWith('BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'))
assert.ok(ics.endsWith('END:VCALENDAR\r\n'))
assert.ok(ics.includes('\r\nDTSTART:20261013T183000Z\r\n'))      // 20:30 CEST = 18:30 UTC
assert.ok(ics.includes('\r\nDTEND:20261013T193000Z\r\n'))
assert.ok(ics.includes('\r\nSUMMARY:Riunione :: budget\\, Q4\\; R&D\\\\ok\r\n'))
assert.ok(ics.includes('\r\nLOCATION:Sala 2\\nPiano 1\r\n'))
assert.ok(ics.includes('\r\nUID:uid-1\r\n'))
assert.ok(ics.includes('\r\nTRIGGER:-PT15M\r\n'))
assert.ok(!M.buildIcs(Object.assign({}, t, { alert: 'none' }), 0, 'u').includes('VALARM'))
assert.ok(M.buildIcs(Object.assign({}, t, { alert: '0m' }), 0, 'u').includes('TRIGGER:PT0S'))
assert.ok(M.buildIcs(Object.assign({}, t, { alert: '1w' }), 0, 'u').includes('TRIGGER:-P1W'))
// after the DST change: 26 Oct 20:30 CET = 19:30 UTC
assert.ok(M.buildIcs(M.moveStart(t, at('2026-10-26T20:30')), 0, 'u').includes('DTSTART:20261026T193000Z'))
// folding: every physical line <= 75 octets, no broken UTF-8
const long = M.buildIcs(Object.assign({}, t, { title: 'è'.repeat(60) }), 0, 'u')
for (const line of long.split('\r\n')) assert.ok(Buffer.byteLength(line, 'utf8') <= 75, line)
assert.ok(!long.includes('\uFFFD'))
assert.equal(long.split('\r\n').filter(l => l.startsWith(' ')).length > 0, true)

// ICS: all day
const allIcs = M.buildIcs(a, 0, 'u')
assert.ok(allIcs.includes('\r\nDTSTART;VALUE=DATE:20261017\r\n'))
assert.ok(allIcs.includes('\r\nDTEND;VALUE=DATE:20261018\r\n'))
assert.ok(allIcs.includes('TRIGGER:PT9H'))
assert.ok(M.buildIcs(Object.assign({}, a, { alert: 'day1' }), 0, 'u').includes('TRIGGER:-PT15H'))
assert.ok(M.buildIcs(Object.assign({}, a, { alert: 'day2' }), 0, 'u').includes('TRIGGER:-P1DT15H'))
assert.ok(M.buildIcs(Object.assign({}, a, { alert: 'week' }), 0, 'u').includes('TRIGGER:-P6DT15H'))

// Presets are what the menus show
assert.deepEqual(M.ALERTS_TIMED.map(x => x.id), ['none', '0m', '5m', '10m', '15m', '30m', '1h', '2h', '1d', '2d', '1w'])
assert.deepEqual(M.ALERTS_ALLDAY.map(x => x.id), ['none', 'day0', 'day1', 'day2', 'week'])
// Transitions (the spec's table)
const closed = M.CLOSED
let s = M.transition(closed, 'clock')
assert.deepEqual(s, { open: true, unfolded: false, sheet: false, sheetReturn: null, day: null, year: false })
assert.equal(M.transition(s, 'clock').open, false)                       // own view: close
assert.equal(M.transition(s, 'pill').unfolded, true)                     // other door: switch
s = M.transition(closed, 'pill')
assert.equal(s.unfolded, true)
assert.equal(M.transition(s, 'pill').open, false)
assert.equal(M.transition(s, 'clock').unfolded, false)
assert.equal(M.transition(s, 'clock').open, true)
const dayView = Object.assign({}, M.transition(closed, 'clock'), { day: '2026-10-13' })
assert.equal(M.transition(dayView, 'clock').day, null)                   // not home: go home
assert.equal(M.transition(dayView, 'clock').open, true)
assert.equal(M.transition(dayView, 'esc').day, null)
const yearView = Object.assign({}, M.transition(closed, 'clock'), { year: true })
assert.equal(M.transition(yearView, 'esc').year, false)
s = M.transition(closed, 'keybind')
assert.equal(s.sheet, true)
assert.equal(s.sheetReturn, 'close')
assert.equal(M.transition(s, 'esc').open, false)                         // opened on the sheet: Esc closes
s = M.transition(dayView, 'keybind')
assert.equal(s.sheetReturn, 'card')
assert.equal(M.transition(s, 'esc').sheet, false)
assert.equal(M.transition(s, 'esc').day, '2026-10-13')                   // back to where it was
assert.equal(M.transition(s, 'keybind').open, false)                     // keybind toggles the sheet
assert.equal(M.transition(s, 'outside').open, false)
assert.equal(M.transition(M.transition(closed, 'clock'), 'esc').open, false)
assert.equal(M.transition(M.openSheet(dayView), 'esc').day, '2026-10-13') // "+" from a day view

// Month grid
const grid = M.monthGrid(2026, 9, 1)
assert.equal(grid.length, 42)
assert.equal(grid[0].key, '2026-09-28')
assert.equal(grid[0].inMonth, false)
const eleventh = grid.findIndex(c => c.key === '2026-10-11')
assert.equal(eleventh % 7, 6)
assert.equal(grid[eleventh].day, 11)
assert.equal(M.monthGrid(2026, 9, 7)[0].key, '2026-09-27')               // Sunday first

// Upcoming
const ev = (title, start, end, allDay) => ({ title, calendar: 'Home', color: '#ff9f0a', location: '',
    startEpoch: at(start), endEpoch: at(end), allDay: !!allDay })
const week = [ev('Gym', '2026-10-11T07:00', '2026-10-11T08:00'), ev('Dentist', '2026-10-11T18:00', '2026-10-11T19:00'),
    ev('Call', '2026-10-13T09:30', '2026-10-13T10:00'), ev('Calcetto', '2026-10-13T20:00', '2026-10-13T22:30'),
    ev('Birthday', '2026-10-17T00:00', '2026-10-18T00:00', true), ev('Later', '2026-10-25T10:00', '2026-10-25T11:00')]
const now = at('2026-10-11T16:52')
assert.deepEqual((({ next, more }) => [next.title, more])(M.upcomingSummary(week, now)), ['Dentist', 3])
assert.equal(M.upcomingSummary([], now).next, null)
const groups = M.groupUpcoming(week, now)
assert.deepEqual(groups.map(g => g.key), ['2026-10-11', '2026-10-13', '2026-10-17'])
assert.deepEqual(groups[0].events.map(e => e.title), ['Dentist'])        // ended ones are gone

// Timeline
const day13 = week.filter(e => M.dayKey(e.startEpoch) === '2026-10-13')
const draft = M.moveStart(Object.assign(M.newDraft(now, defaults), { title: 'Match' }), at('2026-10-13T20:30'))
assert.deepEqual(M.timelineRange([], null, '2026-10-12'), { from: 8, to: 22 })
assert.deepEqual(M.timelineRange(day13, draft, '2026-10-13'), { from: 8, to: 23 })
const early = [ev('Gym', '2026-10-14T07:00', '2026-10-14T08:00'), ev('Flight', '2026-10-14T23:30', '2026-10-15T02:00')]
assert.deepEqual(M.timelineRange(early, null, '2026-10-14'), { from: 7, to: 24 })
assert.deepEqual(M.ticks(8, 22), [8, 12, 16, 20, 22])
assert.deepEqual(M.ticks(6, 24), [6, 10, 14, 18, 22, 24])
assert.deepEqual(M.ticks(8, 23), [8, 12, 16, 20, 23])
assert.deepEqual(M.ticks(8, 21), [8, 12, 16, 21])                     // 20 is too close to the end
const laned = M.lanes([ev('A', '2026-10-13T10:00', '2026-10-13T13:00'), ev('B', '2026-10-13T11:00', '2026-10-13T12:00'),
    ev('C', '2026-10-13T11:30', '2026-10-13T12:30'), ev('D', '2026-10-13T14:00', '2026-10-13T15:00')])
assert.deepEqual(laned.map(e => e.lane), [0, 1, 1, 0])
assert.deepEqual(M.clashes(draft, day13).map(e => e.title), ['Calcetto'])
assert.deepEqual(M.clashes(draft, [ev('Birthday', '2026-10-13T00:00', '2026-10-14T00:00', true)]), [])
// segment of an event within the strip, clipped at the ends
assert.deepEqual(M.segment(early[1], '2026-10-14', { from: 6, to: 24 }), { left: (23.5 - 6) / 18, width: 0.5 / 18, cut: true })

// DST days (TZ=Europe/Rome): the strip counts wall-clock hours
const dstLong = [ev('Late', '2026-10-25T20:00', '2026-10-25T22:30')]
assert.deepEqual(M.timelineRange(dstLong, null, '2026-10-25'), { from: 8, to: 23 })
assert.deepEqual(M.segment(dstLong[0], '2026-10-25', { from: 8, to: 22 }), { left: 12 / 14, width: 2 / 14, cut: true })
assert.deepEqual(M.segment(dstLong[0], '2026-10-25', { from: 8, to: 23 }), { left: 12 / 15, width: 2.5 / 15, cut: false })
const dstShort = [ev('Late', '2027-03-28T20:00', '2027-03-28T22:30')]
assert.deepEqual(M.timelineRange(dstShort, null, '2027-03-28'), { from: 8, to: 23 })
assert.deepEqual(M.segment(dstShort[0], '2027-03-28', { from: 8, to: 23 }), { left: 12 / 15, width: 2.5 / 15, cut: false })
assert.equal(M.escapeText('a;b'), 'a\\;b')

// Drafts: only a new event with a title is kept
assert.equal(M.keepsDraft(Object.assign({}, draft, { title: 'Match' })), true)
assert.equal(M.keepsDraft(Object.assign({}, draft, { title: '   ' })), false)
assert.equal(M.keepsDraft(Object.assign({}, draft, { title: 'Match', mode: 'edit' })), false)
assert.equal(M.keepsDraft(null), false)

// Editing
const listed = { uid: 'calc-1', title: 'Calcetto', location: 'Campo', calendar: 'Home', color: '#ff9f0a',
    startEpoch: at('2026-10-20T20:00'), endEpoch: at('2026-10-20T22:30'), allDay: false, recurring: true }
const info = { alert: 'custom', recurring: true, invitation: false, readOnly: false, hash: 'h1' }
const e1 = M.draftFromEvent(listed, info, defaults)
assert.equal(e1.mode, 'edit')
assert.equal(e1.occurrence, listed.startEpoch)
assert.equal(e1.originalCalendar, 'Home')
assert.equal(e1.alert, 'custom')
assert.equal(M.alertLabel(e1), 'Custom (kept)')
assert.deepEqual(M.alertItems(e1).map(x => x.id).slice(-1), ['custom'])
assert.deepEqual(M.alertItems(M.newDraft(now, defaults)).map(x => x.id).includes('custom'), false)
assert.deepEqual(M.scopeChoices(e1), ['one', 'all'])
assert.deepEqual(M.scopeChoices(Object.assign({}, e1, { calendar: 'Work' })), ['all'])
assert.deepEqual(M.scopeChoices(Object.assign({}, e1, { recurring: false })), [])
assert.deepEqual(M.clashes(e1, [listed]), [])                                   // never with itself
assert.deepEqual(M.clashes(e1, [Object.assign({}, listed, { uid: 'other' })]).length, 1)
assert.deepEqual(Object.keys(M.changesOf(e1)).sort(), ['alert', 'allDay', 'end', 'endDay', 'location', 'start', 'startDay', 'title'])
const allDayListed = Object.assign({}, listed, { allDay: true, startEpoch: at('2026-10-17T00:00'), endEpoch: at('2026-10-19T00:00') })
assert.equal(M.draftFromEvent(allDayListed, info, defaults).endDay, '2026-10-18')       // inclusive last day

console.log('model: ok')
