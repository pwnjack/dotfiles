// Pure model of the media card: it turns Quickshell's MPRIS players into
// everything the card shows, and the QML only draws it. No I/O and no clock:
// the caller passes the position in, in seconds.
//
// A player is read by Quickshell's MprisPlayer property names (dbusName,
// identity, trackTitle, trackArtist, trackAlbum, trackArtUrl, isPlaying,
// length, lengthSupported, canSeek, canTogglePlaying, canGoNext,
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

// The player the bar shows. `wanted` is playerctl's playerName ("spotify",
// "firefox"); a bus name is the prefix, that name and, for some players, an
// instance suffix ("org.mpris.MediaPlayer2.firefox.instance_1_2810"). With no
// match the card still opens: on the first playing player, then the first.
export function pick(players, wanted) {
    const list = players || []
    if (wanted) {
        for (const player of list) {
            const bus = String(player.dbusName || '')
            const name = bus.startsWith(BUS_PREFIX) ? bus.slice(BUS_PREFIX.length) : bus
            if (name === wanted || name.startsWith(wanted + '.')) return player
        }
    }
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
    const player = input.player, players = input.players || []
    if (!player) {
        return {
            title: '', artist: '', album: '', art: '', playing: false, seekRow: false, seekable: false,
            elapsed: '', length: '', seconds: 0, progress: 0,
            canToggle: false, canNext: false, canPrevious: false, chips: [],
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
        // One player needs no picker.
        chips: players.length < 2 ? [] : players.map(other => ({
            label: other.identity || '', player: other, shown: other === player,
        })),
    }
}
