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
assert.ok(ics.includes('\r\nSUMMARY:Riunione :: budget\\, Q4\; R&D\\\\ok\r\n'))
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
console.log('model: ok')
