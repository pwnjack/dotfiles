// Pure model of the weather card: it turns the forecast saved by
// scripts/weather/forecast.sh into everything the card shows, and the QML only
// draws it. No I/O and no clock: callers pass time in, as epoch seconds.
//
// The forecast is Open-Meteo's answer with `timeformat=unixtime`: every time
// is an epoch, and `utc_offset_seconds` is the place's own offset, so hours
// and days are read in the place's time and not this machine's.
//
// Qt's V4 engine imports this file too: no object spread, no optional catch
// binding, no Array.at.

// A saved forecast younger than this opens the card without a request; an
// older one is shown while a new one is fetched. Fifteen minutes is how often
// the bar's own service asks.
export const FRESH_SECONDS = 900

const SUN = '\u{f0599}', NIGHT = '\u{f0594}', PARTLY = '\u{f0595}', NIGHT_PARTLY = '\u{f0f31}'
const CLOUD = '\u{f0590}', FOG = '\u{f0591}', RAIN = '\u{f0597}', POURING = '\u{f0596}'
const SLEET = '\u{f067f}', SNOW = '\u{f0598}', HEAVY_SNOW = '\u{f0f36}', STORM = '\u{f067e}'

// WMO weather codes, as Open-Meteo documents them: [text, day glyph, night glyph].
const CODES = {
    0: ['Clear sky', SUN, NIGHT],
    1: ['Mainly clear', SUN, NIGHT],
    2: ['Partly cloudy', PARTLY, NIGHT_PARTLY],
    3: ['Overcast', CLOUD, CLOUD],
    45: ['Fog', FOG, FOG],
    48: ['Rime fog', FOG, FOG],
    51: ['Light drizzle', RAIN, RAIN],
    53: ['Drizzle', RAIN, RAIN],
    55: ['Dense drizzle', RAIN, RAIN],
    56: ['Freezing drizzle', SLEET, SLEET],
    57: ['Freezing drizzle', SLEET, SLEET],
    61: ['Light rain', RAIN, RAIN],
    63: ['Rain', RAIN, RAIN],
    65: ['Heavy rain', POURING, POURING],
    66: ['Freezing rain', SLEET, SLEET],
    67: ['Freezing rain', SLEET, SLEET],
    71: ['Light snow', SNOW, SNOW],
    73: ['Snow', SNOW, SNOW],
    75: ['Heavy snow', HEAVY_SNOW, HEAVY_SNOW],
    77: ['Snow grains', SNOW, SNOW],
    80: ['Light showers', RAIN, RAIN],
    81: ['Showers', RAIN, RAIN],
    82: ['Violent showers', POURING, POURING],
    85: ['Snow showers', SNOW, SNOW],
    86: ['Heavy snow showers', HEAVY_SNOW, HEAVY_SNOW],
    95: ['Thunderstorm', STORM, STORM],
    96: ['Thunderstorm with hail', STORM, STORM],
    99: ['Thunderstorm with hail', STORM, STORM],
}

// An unknown code names itself: a wrong condition would be worse than an odd one.
export function condition(code, isDay) {
    const known = CODES[code]
    if (!known) return { text: 'Code ' + code, glyph: CLOUD }
    return { text: known[0], glyph: isDay ? known[1] : known[2] }
}

export function fresh(forecast, now) {
    return !!forecast && typeof forecast.fetchedAt === 'number'
        && now - forecast.fetchedAt >= 0 && now - forecast.fetchedAt < FRESH_SECONDS
}

export function age(fetchedAt, now) {
    const seconds = Math.max(0, now - fetchedAt)
    if (seconds < 60) return 'just now'
    if (seconds < 3600) return Math.floor(seconds / 60) + ' min ago'
    if (seconds < 86400) return Math.floor(seconds / 3600) + ' h ago'
    return Math.floor(seconds / 86400) + ' d ago'
}

const isNumber = value => typeof value === 'number' && isFinite(value)
// Math.round(-0.4) is -0, which would print as "0" anyway; "+ 0" keeps it so.
const degrees = value => isNumber(value) ? (Math.round(value) + 0) + '°' : ''
const pad = value => (value < 10 ? '0' : '') + value
// The locale's markers come as "AM", "a.m." or similar; the card's narrow
// slots take the short upper-case form.
const marker = (text, fallback) => String(text || '').replace(/[.\s]/g, '').toUpperCase() || fallback

// The index of the last entry of an ascending epoch list that is not after `now`, or -1.
function lastStarted(times, now) {
    let index = -1
    for (let i = 0; i < times.length && times[i] <= now; i++) index = i
    return index
}

// What the forecast still says about today and later, or null when it has no
// day left: a copy saved days ago must not show a past day as "Today".
function contents(forecast, now, clock, am, pm, dayNames) {
    const daily = forecast && forecast.daily, hourly = forecast && forecast.hourly
    if (!daily || !Array.isArray(daily.time) || !hourly || !Array.isArray(hourly.time)) return null
    const offset = isNumber(forecast.utc_offset_seconds) ? forecast.utc_offset_seconds : 0
    const local = epoch => new Date((epoch + offset) * 1000)
    const twelve = clock === '12h'
    const hourLabel = epoch => {
        const h = local(epoch).getUTCHours()
        return twelve ? (h % 12 === 0 ? 12 : h % 12) + ' ' + (h < 12 ? am : pm) : pad(h)
    }
    const timeLabel = epoch => {
        const h = local(epoch).getUTCHours(), min = pad(local(epoch).getUTCMinutes())
        return twelve ? (h % 12 === 0 ? 12 : h % 12) + ':' + min + ' ' + (h < 12 ? am : pm) : pad(h) + ':' + min
    }

    const today = lastStarted(daily.time, now)
    if (today < 0) return null
    // The last day has no next midnight in the list to end it.
    if (today === daily.time.length - 1 && now >= daily.time[today] + 86400) return null

    // "Now" is the reading taken with the forecast while it is under an hour
    // old, and the forecast's own value for this hour after that.
    const hour = lastStarted(hourly.time, now)
    const hourKnown = hour >= 0 && now < hourly.time[hour] + 3600
    const current = forecast.current
    const live = !!current && isNumber(current.time) && now - current.time >= 0 && now - current.time < 3600
    let temperature = null, feels = null, sky
    if (live) {
        temperature = current.temperature_2m
        feels = current.apparent_temperature
        sky = condition(current.weather_code, current.is_day === 1)
    } else if (hourKnown) {
        temperature = hourly.temperature_2m[hour]
        sky = condition(hourly.weather_code[hour], hourly.is_day[hour] === 1)
    } else {
        sky = condition(daily.weather_code[today], true)
    }

    const hours = []
    for (let step = 0; hourKnown && step < 8 && hour + step * 3 < hourly.time.length; step++) {
        const i = hour + step * 3
        hours.push({
            label: step === 0 ? 'Now' : hourLabel(hourly.time[i]),
            glyph: condition(hourly.weather_code[i], hourly.is_day[i] === 1).glyph,
            temp: degrees(step === 0 && live ? temperature : hourly.temperature_2m[i]),
            now: step === 0,
        })
    }

    // One scale for every row shown, so a warmer day's bar sits further right.
    let coldest = Infinity, warmest = -Infinity
    for (let d = today; d < daily.time.length; d++) {
        if (isNumber(daily.temperature_2m_min[d])) coldest = Math.min(coldest, daily.temperature_2m_min[d])
        if (isNumber(daily.temperature_2m_max[d])) warmest = Math.max(warmest, daily.temperature_2m_max[d])
    }
    const span = warmest - coldest
    const place = value => !isNumber(value) || !(span > 0) ? 0 : Math.max(0, Math.min(1, (value - coldest) / span))
    const days = []
    for (let d = today; d < daily.time.length; d++) {
        const low = daily.temperature_2m_min[d], high = daily.temperature_2m_max[d]
        const rain = daily.precipitation_probability_max ? daily.precipitation_probability_max[d] : null
        days.push({
            label: d === today ? 'Today' : dayNames[local(daily.time[d]).getUTCDay()],
            glyph: condition(daily.weather_code[d], true).glyph,
            rain: isNumber(rain) && rain >= 30 ? Math.round(rain) + '%' : '',
            low: degrees(low),
            high: degrees(high),
            from: place(low),
            to: span > 0 ? place(high) : 1,
            dot: d === today && isNumber(temperature) ? place(temperature) : -1,
        })
    }

    const rise = daily.sunrise ? daily.sunrise[today] : null, set = daily.sunset ? daily.sunset[today] : null
    return {
        title: sky.text,
        glyph: sky.glyph,
        temp: degrees(temperature),
        feels: degrees(feels),
        hours: hours,
        days: days,
        sun: isNumber(rise) && isNumber(set) ? 'Sunrise ' + timeLabel(rise) + ' · Sunset ' + timeLabel(set) : '',
    }
}

// Everything the card draws. Under the title, `place` may be cut short and
// `detail` (how it feels, or why there is no forecast) never is. `phase` is "updating" while a request is under
// way, "ready" after one answered and "failed" after one did not; `reason` is
// forecast.sh's line for a failure. `dayNames` holds seven short names,
// Sunday first; `am` and `pm` are the locale's markers.
export function view(input) {
    const forecast = input.forecast, now = input.now, phase = input.phase
    const shown = forecast ? contents(forecast, now, input.clock,
        marker(input.am, 'AM'), marker(input.pm, 'PM'), input.dayNames || []) : null
    if (!shown) {
        const waiting = phase === 'updating'
        return {
            title: waiting ? 'Weather' : 'No forecast',
            place: '',
            detail: waiting ? 'Loading the forecast…' : input.reason || 'The saved forecast is too old.',
            glyph: CLOUD, temp: '', hours: [], days: [], sun: '', note: '', warn: false,
        }
    }
    // The bar's name for the place is "City, Country" and the card has room
    // for the city. A name with no city before the comma is shown as it is.
    const named = typeof forecast.place === 'string' ? forecast.place.replace(/^[,\s]+/, '') : ''
    const place = named.split(',')[0].trim()
    const feels = shown.feels ? 'feels like ' + shown.feels : ''
    const updated = isNumber(forecast.fetchedAt) ? 'updated ' + age(forecast.fetchedAt, now) : ''
    let note = updated.charAt(0).toUpperCase() + updated.slice(1)
    if (phase === 'updating') note = 'Updating…'
    else if (phase === 'failed') note = updated ? 'Offline · ' + updated : 'Offline'
    return {
        title: shown.title, place: place, glyph: shown.glyph, temp: shown.temp,
        // After the place it reads on in lower case; alone it starts the line.
        detail: place ? feels : feels.charAt(0).toUpperCase() + feels.slice(1),
        hours: shown.hours, days: shown.days, sun: shown.sun,
        note: note, warn: phase === 'failed',
    }
}
