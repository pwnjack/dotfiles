import assert from 'node:assert/strict'
import * as model from '../model.mjs'

// Two players in the shape Quickshell reported on 21 November 2026: a music
// player under its plain name, and a browser under a name with an instance.
function music(overrides) {
    return Object.assign({
        dbusName: 'org.mpris.MediaPlayer2.spotify', identity: 'Spotify',
        trackTitle: 'Night Drive', trackArtist: 'Example Artist', trackAlbum: 'Example Album',
        trackArtUrl: 'https://images.example/cover.jpg', isPlaying: true, uniqueId: 7,
        length: 220, lengthSupported: true, canSeek: true,
        canTogglePlaying: true, canGoNext: true, canGoPrevious: true,
    }, overrides)
}
function browser(overrides) {
    return Object.assign({
        dbusName: 'org.mpris.MediaPlayer2.firefox.instance_1_2810', identity: 'Mozilla zen',
        trackTitle: 'A video', trackArtist: 'A channel', trackAlbum: '',
        trackArtUrl: 'file:///home/user/.zen/firefox-mpris/1_2.png', isPlaying: false,
        length: 134, lengthSupported: true, canSeek: true,
        canTogglePlaying: true, canGoNext: false, canGoPrevious: false,
    }, overrides)
}
const view = (player, position) => model.view({ player, position: position || 0 })

// The bar's player, by playerctl's name.
{
    const spotify = music(), zen = browser()
    assert.equal(model.pick([zen, spotify], 'spotify'), spotify, 'the exact name')
    assert.equal(model.pick([spotify, zen], 'firefox'), zen, 'the name before an instance suffix')
    assert.equal(model.pick([zen, spotify], 'spot'), spotify, 'part of a name is no match: the playing one')
    assert.equal(model.pick([zen, spotify], 'vlc'), spotify, 'no match: the first playing player')
    assert.equal(model.pick([zen, music({ isPlaying: false })], ''), zen, 'nothing playing: the first')
    assert.equal(model.pick([], 'spotify'), null)
    assert.equal(model.pick(null, ''), null)
    // A name that only starts like the wanted one belongs to another player.
    const other = music({ dbusName: 'org.mpris.MediaPlayer2.firefoxnightly', isPlaying: false })
    assert.equal(model.pick([other, zen], 'firefox'), zen)
    // `named` is the match alone: the card waits for it before it settles.
    assert.equal(model.named([zen, spotify], 'spotify'), spotify)
    assert.equal(model.named([zen, spotify], 'vlc'), null)
    assert.equal(model.named([zen, spotify], ''), null)
    assert.equal(model.named(null, 'spotify'), null)
}

// Times.
{
    assert.equal(model.time(5), '0:05')
    assert.equal(model.time(220.9), '3:40')
    assert.equal(model.time(3723), '1:02:03')
    assert.equal(model.time(-4), '0:00')
    assert.equal(model.time(undefined), '0:00')
}

// A track with everything.
{
    const v = view(music(), 72)
    assert.deepEqual([v.title, v.artist, v.album], ['Night Drive', 'Example Artist', 'Example Album'])
    assert.deepEqual([v.elapsed, v.length, v.seconds], ['1:12', '3:40', 220])
    assert.ok(Math.abs(v.progress - 72 / 220) < 1e-9)
    assert.deepEqual([v.seekRow, v.seekable, v.playing], [true, true, true])
    assert.deepEqual([v.canToggle, v.canNext, v.canPrevious], [true, true, true])
}

// The track's key changes with the track, and with nothing else.
{
    const key = view(music(), 10).track
    assert.equal(view(music(), 99).track, key, 'not with the position')
    assert.equal(view(music({ isPlaying: false }), 10).track, key, 'not with a pause')
    assert.notEqual(view(music({ uniqueId: 8 }), 10).track, key)
    assert.notEqual(view(music({ trackTitle: 'Another' }), 10).track, key)
    assert.notEqual(view(music({ length: 221 }), 10).track, key)
}

// The position never leaves the bar.
{
    assert.equal(view(music(), 999).progress, 1)
    assert.equal(view(music(), 999).elapsed, '3:40')
    assert.equal(view(music(), -3).progress, 0)
}

// No length: no seek row. A length the player cannot seek in: a row that
// takes no input.
{
    for (const stream of [music({ length: 0 }), music({ lengthSupported: false }), music({ length: -1 })]) {
        const v = view(stream, 30)
        assert.deepEqual([v.seekRow, v.seekable, v.progress], [false, false, 0])
    }
    const fixed = view(music({ canSeek: false }), 30)
    assert.deepEqual([fixed.seekRow, fixed.seekable], [true, false])
}

// Art: a local file or HTTPS, nothing else.
{
    assert.equal(view(music()).art, 'https://images.example/cover.jpg')
    assert.equal(view(browser()).art, 'file:///home/user/.zen/firefox-mpris/1_2.png')
    for (const url of ['http://images.example/cover.jpg', 'data:image/png;base64,AAAA', 'ftp://host/a.png', '', undefined])
        assert.equal(view(music({ trackArtUrl: url })).art, '', String(url))
}

// What a browser tab cannot do is off, and an empty title names the player.
{
    const v = view(browser())
    assert.deepEqual([v.canToggle, v.canNext, v.canPrevious, v.playing], [true, false, false, false])
    assert.equal(v.album, '')
    assert.equal(view(music({ trackTitle: '' })).title, 'Spotify')
}

// Two players: a chip each, in bus order.
{
    const spotify = music(), zen = browser()
    const chips = model.chips([spotify, zen])
    assert.deepEqual(chips.map(chip => chip.label), ['Spotify', 'Mozilla zen'])
    assert.deepEqual(chips.map(chip => chip.player), [spotify, zen])
    assert.deepEqual(model.chips([spotify]), [], 'one player needs no picker')
    assert.deepEqual(model.chips(null), [])
}

// No player at all: an empty view, nothing to press.
{
    const v = model.view({ player: null, position: 0 })
    assert.deepEqual([v.title, v.seekRow, v.canToggle], ['', false, false])
}

// Seeking: a release on the bar, and the keys' steps.
{
    assert.equal(model.seek(0.5, 220), 110)
    assert.equal(model.seek(1.4, 220), 220)
    assert.equal(model.seek(-0.2, 220), 0)
    assert.equal(model.seek(0.5, 0), 0)
    assert.equal(model.step(100, model.STEP_SECONDS, 220), 105)
    assert.equal(model.step(2, -model.STEP_SECONDS, 220), 0)
    assert.equal(model.step(218, model.STEP_SECONDS, 220), 220)
}

console.log('media card model: ok')
