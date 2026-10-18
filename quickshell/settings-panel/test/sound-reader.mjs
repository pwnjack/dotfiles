import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'
import * as CalendarRead from '../calendar.mjs'

// The Sound page's reader lives in shell.qml; its real code runs here against a stand-in
// for the root object, as test/about.mjs does for the About reader.
const shell = fs.readFileSync(new URL('../shell.qml', import.meta.url), 'utf8')
function between(start, end, from = 0) {
    const at = shell.indexOf(start, from)
    assert.ok(at >= 0, `shell.qml has ${start}`)
    return shell.slice(at + start.length, shell.indexOf(end, at))
}
const shownChanged = between('onSoundShownChanged: {', '\n    }')
const readFn = shell.slice(shell.indexOf('function readSound('), shell.indexOf('\n    Process {', shell.indexOf('function readSound(')))
const exited = between('onExited: code => {', '\n        }\n    }', shell.indexOf('id: soundReader'))

// The root's properties are bare names inside its own functions and handlers, and `root.x` outside them.
const context = {
    opened: true, closing: false, category: 'sound', query: '', busy: false, soundGeneration: 0,
    get soundShown() { return this.opened && !this.closing && this.category === 'sound' && !this.query.trim() },
    sound: {defaultSink: 'old'}, soundError: '',
    soundReader: {running: false, generation: -1, reply: '', errorText: ''},
    soundTimer: {stop() {}, restart() {}},
    CalendarRead, console: {warn() {}}, generation: -1, code: 0,
}
context.root = context
vm.createContext(context)
vm.runInContext(readFn, context)
const run = code => vm.runInContext('(function () {' + code + '})()', context)
// The Process's own `generation` is a bare name inside its onExited.
const land = (reply, code = 0, errorText = '') => {
    context.code = code
    context.soundReader.errorText = errorText
    context.soundReader.reply = typeof reply === 'string' ? reply : JSON.stringify(reply)
    context.generation = context.soundReader.generation
    context.soundReader.running = false
    run(exited)
}
const devices = defaultSink => ({ok: true, sound: {outputs: [], inputs: [], defaultSink}})

// A read that lands while the page is still shown replaces the devices.
vm.runInContext('readSound()', context)
assert.equal(context.soundReader.running, true)
assert.equal(context.soundReader.generation, 0)
land(devices('fresh'))
assert.equal(context.sound.defaultSink, 'fresh')

// Hidden and shown again before the reply lands: the older read is dropped.
vm.runInContext('readSound()', context)
const startedUnder = context.soundReader.generation
context.category = 'appearance'
run(shownChanged)
assert.equal(context.soundGeneration, startedUnder + 1, 'hiding the page bumps the generation')
assert.equal(context.soundReader.running, false, 'and stops the read in flight')
context.category = 'sound'
land(devices('stale'))
assert.equal(context.soundReader.generation, startedUnder)
assert.equal(context.sound.defaultSink, 'fresh', 'a reply from before the page was hidden is not applied')

// Nothing lands while the page is hidden, even from the current generation.
vm.runInContext('readSound()', context)
context.category = 'appearance'
land(devices('hidden'))
assert.equal(context.sound.defaultSink, 'fresh')
context.category = 'sound'

// A failed or malformed reply keeps what is shown and says why.
assert.equal(context.soundError, '', 'a good read leaves no error')
vm.runInContext('readSound()', context)
land({ok: false, error: 'pactl failed'})
assert.equal(context.sound.defaultSink, 'fresh')
assert.equal(context.soundError, 'Could not read audio devices: pactl failed')
vm.runInContext('readSound()', context)
land('not json')
assert.equal(context.sound.defaultSink, 'fresh')
assert.equal(context.soundError, 'Could not read audio devices: the settings helper exited 0 without a usable reply')
vm.runInContext('readSound()', context)
land('', 3, 'noise\nbash: panel-request.sh: not found\n')
assert.equal(context.soundError, 'Could not read audio devices: bash: panel-request.sh: not found', 'stderr names a helper that died silently')
vm.runInContext('readSound()', context)
land({ok: true, sound: {defaultSink: 'nonzero'}}, 1)
assert.equal(context.sound.defaultSink, 'fresh', 'a non-zero exit is a failure even with a reply')
assert.ok(context.soundError)
vm.runInContext('readSound()', context)
land({ok: true})
assert.equal(context.soundError, 'Could not read audio devices: the settings helper exited 0 without a usable reply', 'a reply with no sound is a failure')

// The next good read clears the error and updates the devices.
vm.runInContext('readSound()', context)
land(devices('recovered'))
assert.equal(context.soundError, '')
assert.equal(context.sound.defaultSink, 'recovered')

// A failed read from an older generation sets nothing.
vm.runInContext('readSound()', context)
context.category = 'appearance'
run(shownChanged)
context.category = 'sound'
land({ok: false, error: 'late failure'})
assert.equal(context.soundError, '', 'a stale failure shows no error')
assert.equal(context.sound.defaultSink, 'recovered')

// No read starts while a write is in flight (it reads again when the queue drains).
context.busy = true; context.soundReader.running = false
vm.runInContext('readSound()', context)
assert.equal(context.soundReader.running, false)
console.log('ok: sound reader drops stale replies')
