// Pure model of the media card: it turns Quickshell's MPRIS players into
// everything the card shows, and the QML only draws it. No I/O and no clock:
// the caller passes the position in, in seconds.
//
// A player is read by Quickshell's MprisPlayer property names (dbusName,
// identity, trackTitle, trackArtist, trackAlbum, trackArtUrl, isPlaying,
// uniqueId, length, lengthSupported, canSeek, canTogglePlaying, canGoNext,
// canGoPrevious). Lengths and positions are seconds.
//
// Qt's V4 engine imports this file too: no object spread, no optional catch
// binding, no Array.at.

const BUS_PREFIX = 'org.mpris.MediaPlayer2.'

// What Left and Right move playback by.
export const STEP_SECONDS = 5

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value))
}

// The player the bar shows, or null while it is not on the list. `wanted` is
// playerctl's playerName ("spotify", "firefox"); a bus name is the prefix,
// that name and, for some players, an instance suffix
// ("org.mpris.MediaPlayer2.firefox.instance_1_2810").
export function named(players, wanted) {
    if (!wanted) return null
    for (const player of players || []) {
        const bus = String(player.dbusName || '')
        const name = bus.startsWith(BUS_PREFIX) ? bus.slice(BUS_PREFIX.length) : bus
        if (name === wanted || name.startsWith(wanted + '.')) return player
    }
    return null
}

// The player the card shows: the bar's, and without it the card still has
// one, the first playing player, then the first.
export function pick(players, wanted) {
    const list = players || [], match = named(list, wanted)
    if (match) return match
    for (const player of list) if (player.isPlaying) return player
    return list.length ? list[0] : null
}

// "0:05", "3:40", and "1:02:03" from one hour.
export function time(seconds) {
    const whole = Math.max(0, Math.floor(Number(seconds) || 0))
    const hours = Math.floor(whole / 3600), minutes = Math.floor(whole % 3600 / 60)
    const two = value => String(value).padStart(2, '0')
    return hours > 0 ? hours + ':' + two(minutes) + ':' + two(whole % 60) : minutes + ':' + two(whole % 60)
}

// Where a release at `fraction` of the bar lands, in seconds.
export function seek(fraction, length) {
    return clamp(Number(fraction) || 0, 0, 1) * Math.max(0, Number(length) || 0)
}

// Where a step of `delta` seconds from `position` lands.
export function step(position, delta, length) {
    return clamp((Number(position) || 0) + delta, 0, Math.max(0, Number(length) || 0))
}

// Any program on the session bus can name an art URL, so only a local file
// and HTTPS are loaded; everything else shows the placeholder.
function art(url) {
    return /^(https|file):/i.test(String(url || '')) ? String(url) : ''
}

export function view(input) {
    const player = input.player
    if (!player) {
        return {
            title: '', artist: '', album: '', art: '', track: '', playing: false, seekRow: false, seekable: false,
            elapsed: '', length: '', seconds: 0, progress: 0,
            canToggle: false, canNext: false, canPrevious: false,
        }
    }
    const length = player.lengthSupported && player.length > 0 ? player.length : 0
    const position = clamp(Number(input.position) || 0, 0, length)
    return {
        // Spotify sits on the bus without a title in some states: name the
        // player instead of showing an empty card.
        title: player.trackTitle || player.identity || '',
        artist: player.trackArtist || '',
        album: player.trackAlbum || '',
        art: art(player.trackArtUrl),
        // Changes when the track does: a thumb held across it is let go.
        track: [player.uniqueId, player.trackTitle, length].join('\n'),
        playing: !!player.isPlaying,
        seekRow: length > 0,
        seekable: length > 0 && !!player.canSeek,
        elapsed: time(position),
        length: time(length),
        seconds: length,
        progress: length > 0 ? position / length : 0,
        canToggle: !!player.canTogglePlaying,
        canNext: !!player.canGoNext,
        canPrevious: !!player.canGoPrevious,
    }
}

// One chip per player, in bus order; one player needs no picker. The list
// depends on the players alone, not on the one shown or its position: the
// card rebuilds its chips, and drops the focus on one, whenever this changes.
export function chips(players) {
    const list = players || []
    return list.length < 2 ? [] : list.map(player => ({ label: player.identity || '', player: player }))
}
