import assert from 'node:assert/strict'
import * as model from '../model.mjs'

// Two players in the shape Quickshell reported on 21 November 2026: a music
// player under its plain name, and a browser under a name with an instance.
function music(overrides) {
    return Object.assign({
        dbusName: 'org.mpris.MediaPlayer2.spotify', identity: 'Spotify',
        trackTitle: 'Night Drive', trackArtist: 'Example Artist', trackAlbum: 'Example Album',
        trackArtUrl: 'https://images.example/cover.jpg', isPlaying: true,
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
const view = (player, players, position) => model.view({ player, players: players || [player], position: position || 0 })

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
    const v = view(music(), null, 72)
    assert.deepEqual([v.title, v.artist, v.album], ['Night Drive', 'Example Artist', 'Example Album'])
    assert.deepEqual([v.elapsed, v.length, v.seconds], ['1:12', '3:40', 220])
    assert.ok(Math.abs(v.progress - 72 / 220) < 1e-9)
    assert.deepEqual([v.seekRow, v.seekable, v.playing], [true, true, true])
    assert.deepEqual([v.canToggle, v.canNext, v.canPrevious], [true, true, true])
    assert.deepEqual(v.chips, [], 'one player needs no picker')
}

// The position never leaves the bar.
{
    assert.equal(view(music(), null, 999).progress, 1)
    assert.equal(view(music(), null, 999).elapsed, '3:40')
    assert.equal(view(music(), null, -3).progress, 0)
}

// No length: no seek row. A length the player cannot seek in: a row that
// takes no input.
{
    for (const stream of [music({ length: 0 }), music({ lengthSupported: false }), music({ length: -1 })]) {
        const v = view(stream, null, 30)
        assert.deepEqual([v.seekRow, v.seekable, v.progress], [false, false, 0])
    }
    const fixed = view(music({ canSeek: false }), null, 30)
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

// Two players: a chip each, in bus order, the shown one marked.
{
    const spotify = music(), zen = browser()
    const v = view(zen, [spotify, zen])
    assert.deepEqual(v.chips.map(chip => chip.label), ['Spotify', 'Mozilla zen'])
    assert.deepEqual(v.chips.map(chip => chip.shown), [false, true])
    assert.equal(v.chips[0].player, spotify)
}

// No player at all: an empty view, nothing to press.
{
    const v = model.view({ player: null, players: [], position: 0 })
    assert.deepEqual([v.title, v.seekRow, v.canToggle, v.chips.length], ['', false, false, 0])
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
