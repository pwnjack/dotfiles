import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import * as model from '../model.mjs'

// Open-Meteo's answer for Berlin as forecast.sh saved it: fetched on Thursday
// 19 November 2026 at 21:56 local time (UTC+1), with its hours starting at 21:00.
const forecast = JSON.parse(readFileSync(new URL('./fixtures/forecast.json', import.meta.url), 'utf8'))
const NOW = forecast.fetchedAt + 36
const DAY = 86400
const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
const RAIN = '\u{f0597}', CLOUD = '\u{f0590}', PARTLY = '\u{f0595}', NIGHT = '\u{f0594}'

function view(overrides) {
    return model.view(Object.assign({
        forecast, now: NOW, clock: '24h', am: 'AM', pm: 'PM', dayNames, phase: 'ready', reason: '',
    }, overrides))
}
const column = (rows, key) => rows.map(row => row[key])
const near = (actual, expected, label) => assert.ok(Math.abs(actual - expected) < 0.0005, `${label}: ${actual}`)

// The forecast as fetched: header, eight slots, seven rows.
{
    const v = view()
    assert.equal(v.title, 'Light rain')
    assert.deepEqual([v.place, v.detail], ['Berlin', 'feels like 5°'])
    assert.equal(v.glyph, RAIN)
    assert.equal(v.temp, '8°')
    assert.equal(v.note, 'Updated just now')
    assert.equal(v.warn, false)
    assert.equal(v.sun, 'Sunrise 07:34 · Sunset 16:07')

    // Three hours apart from the current hour; the first is the reading itself.
    assert.deepEqual(column(v.hours, 'label'), ['Now', '00', '03', '06', '09', '12', '15', '18'])
    assert.deepEqual(column(v.hours, 'temp'), ['8°', '6°', '5°', '4°', '4°', '5°', '5°', '4°'])
    assert.deepEqual(column(v.hours, 'now'), [true, false, false, false, false, false, false, false])
    assert.deepEqual(column(v.hours, 'glyph'), [RAIN, RAIN, CLOUD, CLOUD, CLOUD, CLOUD, PARTLY, NIGHT])

    assert.deepEqual(column(v.days, 'label'), ['Today', 'Fri', 'Sat', 'Sun', 'Mon', 'Tue', 'Wed'])
    // Rain shows from 30% up: 19, 20, 7 and 11 stay blank.
    assert.deepEqual(column(v.days, 'rain'), ['100%', '68%', '', '33%', '', '', ''])
    assert.deepEqual(column(v.days, 'low'), ['6°', '2°', '0°', '3°', '0°', '-1°', '-2°'])
    assert.deepEqual(column(v.days, 'high'), ['10°', '6°', '7°', '6°', '4°', '2°', '2°'])
    // One scale for the week: -2.4 (Wednesday's low) to 9.8 (today's high).
    near(v.days[0].from, 8 / 12.2, 'today from')
    assert.equal(v.days[0].to, 1)
    assert.equal(v.days[6].from, 0)
    near(v.days[6].to, 4.3 / 12.2, 'last to')
    // The dot is the temperature now, on today's row only.
    near(v.days[0].dot, 10.3 / 12.2, 'dot')
    assert.deepEqual(column(v.days, 'dot').slice(1), [-1, -1, -1, -1, -1, -1])
    v.days.forEach(day => assert.ok(day.from >= 0 && day.from <= day.to && day.to <= 1))
}

// The dot stays on the track when it is warmer or colder now than any forecast.
{
    const hot = JSON.parse(JSON.stringify(forecast)); hot.current.temperature_2m = 30
    assert.equal(view({ forecast: hot }).days[0].dot, 1)
    const cold = JSON.parse(JSON.stringify(forecast)); cold.current.temperature_2m = -20
    assert.equal(view({ forecast: cold }).days[0].dot, 0)
}

// Rain that began after the hour's forecast was made: the first slot shows
// what the header shows, and the later slots keep their own forecast.
{
    const wet = JSON.parse(JSON.stringify(forecast))
    wet.hourly.weather_code[0] = 3
    const v = view({ forecast: wet })
    assert.equal(v.glyph, RAIN)
    assert.equal(v.hours[0].glyph, RAIN)
    assert.equal(v.hours[2].glyph, CLOUD)
}

// The three phases over a forecast.
{
    assert.equal(view({ phase: 'updating' }).note, 'Updating…')
    assert.equal(view({ phase: 'updating' }).warn, false)
    const offline = view({ phase: 'failed', now: NOW + 2 * 3600, reason: 'No connection to Open-Meteo.' })
    assert.equal(offline.note, 'Offline · updated 2 h ago')
    assert.equal(offline.warn, true)
    assert.equal(offline.days.length, 7)
}

// A copy a day old: yesterday and the past hours are gone, and "now" is the
// forecast's value for this hour, with nothing to say about how it feels.
{
    const v = view({ now: NOW + DAY, phase: 'failed' })
    assert.deepEqual(column(v.days, 'label'), ['Today', 'Sat', 'Sun', 'Mon', 'Tue', 'Wed'])
    assert.equal(v.title, 'Mainly clear')
    assert.equal(v.glyph, NIGHT)
    assert.equal(v.temp, '3°')
    assert.deepEqual([v.place, v.detail], ['Berlin', ''])
    assert.deepEqual(column(v.hours, 'label'), ['Now', '00', '03', '06', '09', '12', '15', '18'])
    assert.equal(v.hours[0].temp, '3°')
    assert.equal(v.sun, 'Sunrise 07:36 · Sunset 16:06')
    assert.equal(v.note, 'Offline · updated 1 d ago')
    // The scale is now over the six days left: -2.4 to 6.5.
    near(v.days[0].dot, 4.9 / 8.9, 'dot a day later')
}

// A copy with fewer than 21 hours left shows the slots it has; with no hour
// left it shows none, and takes the day's own condition for the header.
{
    assert.equal(view({ now: NOW + DAY + 6 * 3600 }).hours.length, 6)
    const v = view({ now: NOW + 2 * DAY + 3 * 3600 })
    assert.deepEqual(v.hours, [])
    assert.equal(v.temp, '')
    assert.equal(v.title, 'Light showers')
    assert.equal(v.days.length, 4)
    assert.equal(v.days[0].dot, -1)
}

// No day left, or no forecast at all: the two views without rows.
{
    const old = view({ now: NOW + 8 * DAY, phase: 'failed', reason: 'No connection to Open-Meteo.' })
    assert.equal(old.title, 'No forecast')
    assert.deepEqual([old.place, old.detail], ['', 'No connection to Open-Meteo.'])
    assert.deepEqual([old.temp, old.hours, old.days, old.sun, old.note, old.warn], ['', [], [], '', '', false])
    assert.equal(old.glyph, CLOUD)
    // The last day ends at its own midnight, not when the list does.
    assert.equal(view({ now: forecast.daily.time[6] + DAY - 1 }).days.length, 1)
    assert.equal(view({ now: forecast.daily.time[6] + DAY }).title, 'No forecast')
    // A clock before the forecast's first day has no "today" in it either.
    assert.equal(view({ now: forecast.daily.time[0] - 1 }).title, 'No forecast')

    const loading = view({ forecast: null, phase: 'updating' })
    assert.equal(loading.title, 'Weather')
    assert.equal(loading.detail, 'Loading the forecast…')
    assert.deepEqual(loading.days, [])
    const failed = view({ forecast: null, phase: 'failed', reason: 'The bar has no location yet.' })
    assert.equal(failed.title, 'No forecast')
    assert.equal(failed.detail, 'The bar has no location yet.')
    assert.equal(view({ forecast: {}, phase: 'failed', reason: 'x' }).title, 'No forecast')
}

// 12-hour clock, with the locale's markers in whatever form it has them.
{
    const v = view({ clock: '12h', am: 'a.m.', pm: 'p.m.' })
    assert.deepEqual(column(v.hours, 'label'), ['Now', '12 AM', '3 AM', '6 AM', '9 AM', '12 PM', '3 PM', '6 PM'])
    assert.equal(v.sun, 'Sunrise 7:34 AM · Sunset 4:07 PM')
    assert.equal(view({ clock: '12h', am: '', pm: '' }).hours[1].label, '12 AM')
}

// Times are the place's, whatever this machine's zone: the same forecast read
// as if Berlin were at UTC-5 moves every label by six hours.
{
    const moved = JSON.parse(JSON.stringify(forecast)); moved.utc_offset_seconds = -5 * 3600
    assert.equal(view({ forecast: moved }).hours[1].label, '18')
}

// The place and the feeling are each optional.
{
    const bare = JSON.parse(JSON.stringify(forecast)); delete bare.place
    assert.deepEqual([view({ forecast: bare }).place, view({ forecast: bare }).detail], ['', 'Feels like 5°'])
    assert.equal(view({ forecast: bare, now: NOW + DAY }).detail, '')
    // The bar names a place "City, Country"; a place with no city keeps what it has.
    const named = place => view({ forecast: Object.assign({}, forecast, { place }) }).place
    assert.equal(named('San Pedro de Atacama, Chile'), 'San Pedro de Atacama')
    assert.equal(named(', Italy'), 'Italy')
    assert.equal(named('Berlin'), 'Berlin')
}

// Conditions: day and night glyphs, and a code this table does not know.
assert.deepEqual(model.condition(0, true), { text: 'Clear sky', glyph: '\u{f0599}' })
assert.deepEqual(model.condition(0, false), { text: 'Clear sky', glyph: NIGHT })
assert.deepEqual(model.condition(2, false), { text: 'Partly cloudy', glyph: '\u{f0f31}' })
assert.deepEqual(model.condition(95, true), { text: 'Thunderstorm', glyph: '\u{f067e}' })
assert.deepEqual(model.condition(42, true), { text: 'Code 42', glyph: CLOUD })
// Every code Open-Meteo documents has a name and a glyph for day and night.
for (const code of [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99]) {
    for (const isDay of [true, false]) {
        const sky = model.condition(code, isDay)
        assert.ok(!sky.text.startsWith('Code') && sky.glyph.codePointAt(0) >= 0xf0000, `code ${code}`)
    }
}

// Fresh for fifteen minutes, and never for a copy from the future.
assert.equal(model.fresh(forecast, forecast.fetchedAt + 14 * 60), true)
assert.equal(model.fresh(forecast, forecast.fetchedAt + 16 * 60), false)
assert.equal(model.fresh(forecast, forecast.fetchedAt - 1), false)
assert.equal(model.fresh(null, NOW), false)
assert.equal(model.fresh({}, NOW), false)

assert.equal(model.age(1000, 1059), 'just now')
assert.equal(model.age(1000, 1000 + 4 * 60 + 30), '4 min ago')
assert.equal(model.age(1000, 1000 + 3 * 3600 + 59), '3 h ago')
assert.equal(model.age(1000, 1000 + 2 * DAY + 5), '2 d ago')
assert.equal(model.age(1000, 900), 'just now')

console.log('weather model: ok')
