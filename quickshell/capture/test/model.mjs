import assert from 'node:assert/strict'
import * as M from '../model.mjs'

const files = { 'capture-shot-target': 'window\n', 'capture-rec-target': 'region\n', 'capture-delay': '5\n',
    'capture-freeze': 'true\n', 'capture-annotate': 'false\n', 'capture-audio': 'true\n', 'capture-mic': 'no\n' }

// Options: read, defaults, invalid values.
{
    const s = M.parseOptions(files)
    assert.deepEqual(s, { shotTarget: 'window', recTarget: 'region', delay: 5, freeze: true, annotate: false, audio: true, mic: false })
    assert.deepEqual(M.parseOptions({}), { shotTarget: 'region', recTarget: 'screen', delay: 0, freeze: false, annotate: false, audio: false, mic: false })
    const bad = M.parseOptions({ 'capture-shot-target': 'everything', 'capture-delay': '-2', 'capture-freeze': 'yes' })
    assert.equal(bad.shotTarget, 'region')
    assert.equal(bad.delay, 0)
    assert.equal(bad.freeze, false)
    assert.equal(M.parseOptions({ 'capture-delay': '7' }).delay, 7, 'a hand-written delay is shown as it is')
}

// Initial state and modes.
{
    assert.equal(M.initialState(files, 'record').mode, 'record')
    assert.equal(M.initialState(files, 'nonsense').mode, 'screenshot')
    assert.equal(M.withMode(M.initialState({}, 'screenshot'), 'bogus').mode, 'screenshot')
    assert.deepEqual(M.controls('screenshot'), ['delay', 'freeze', 'annotate'])
    assert.deepEqual(M.controls('record'), ['delay', 'audio', 'mic'])
    assert.deepEqual(M.controls('text'), ['delay', 'freeze'])
    assert.deepEqual(M.MODES, ['screenshot', 'text', 'record'])
    assert.equal(M.initialState(files, 'text').mode, 'text')
}

// Delay cycle and label.
{
    assert.deepEqual([0, 3, 5, 10].map(M.nextDelay), [3, 5, 10, 0])
    assert.equal(M.nextDelay(7), 10)
    assert.equal(M.delayLabel(0), 'Off')
    assert.equal(M.delayLabel(10), '10s')
}

// setOption writes only on change, as the option file's text.
{
    const s = M.initialState({}, 'screenshot')
    const r = M.setOption(s, 'freeze', true)
    assert.equal(r.state.freeze, true)
    assert.deepEqual(r.write, ['capture-freeze', 'true'])
    assert.equal(M.setOption(r.state, 'freeze', true).write, null)
    assert.deepEqual(M.setOption(s, 'delay', 3).write, ['capture-delay', '3'])
    assert.deepEqual(M.setOption(s, 'recTarget', 'window').write, ['capture-rec-target', 'window'])
}

// Keyboard.
{
    let s = M.initialState({}, 'screenshot')            // shot target: region (index 2)
    let r = M.reduceKey(s, 'Right')
    assert.equal(r.state.shotTarget, 'region', 'Right clamps at the end')
    assert.equal(r.write, null)
    r = M.reduceKey(s, 'Left')
    assert.equal(r.state.shotTarget, 'window')
    assert.deepEqual(r.write, ['capture-shot-target', 'window'])
    assert.equal(r.effect, 'none')
    r = M.reduceKey(r.state, 'Tab')
    assert.equal(r.state.mode, 'text', 'Tab goes Screenshot -> Text')
    r = M.reduceKey(r.state, 'Tab')
    assert.equal(r.state.mode, 'record')
    assert.equal(r.state.recTarget, 'screen', 'each mode keeps its own target')
    r = M.reduceKey(r.state, 'Left')
    assert.equal(r.state.recTarget, 'screen', 'Left clamps at the start')
    r = M.reduceKey(r.state, 'Tab')
    assert.equal(r.state.mode, 'screenshot', 'Tab wraps round')
    assert.equal(r.state.shotTarget, 'window', 'switching back restores the screenshot target')
    r = M.reduceKey(r.state, 'Backtab')
    assert.equal(r.state.mode, 'record', 'Shift+Tab wraps backwards from Screenshot')
    r = M.reduceKey(r.state, 'Backtab')
    assert.equal(r.state.mode, 'text')
    r = M.reduceKey(r.state, 'Backtab')
    assert.equal(r.state.mode, 'screenshot')
    const text = M.initialState({}, 'text')
    for (const name of ['Left', 'Right']) {
        r = M.reduceKey(text, name)
        assert.equal(r.state, text, name + ' does nothing on Text')
        assert.equal(r.write, null)
        assert.equal(r.effect, 'none')
    }
    assert.equal(M.reduceKey(text, 'Return').effect, 'run')
    assert.equal(M.reduceKey(s, 'Return').effect, 'run')
    assert.equal(M.reduceKey(s, 'Escape').effect, 'close')
    assert.equal(M.reduceKey(s, 'q').effect, 'none')
}

// Status, action label and the command.
{
    const idle = M.parseStatus('')
    assert.deepEqual(idle, { phase: 'idle', seconds: 0 })
    assert.deepEqual(M.parseStatus('{"text":"x","class":"recording","phase":"recording","seconds":42}'), { phase: 'recording', seconds: 42 })
    assert.deepEqual(M.parseStatus('not json'), idle)
    const rec = M.initialState({}, 'record')
    const shot = M.initialState({}, 'screenshot')
    assert.equal(M.action(shot, idle).label, 'Capture')
    assert.equal(M.action(shot, { phase: 'recording', seconds: 5 }).label, 'Capture', 'the Screenshot tab works normally while recording')
    assert.equal(M.action(rec, idle).label, 'Record')
    assert.equal(M.action(rec, { phase: 'recording', seconds: 42 }).label, 'Stop 0:42')
    assert.equal(M.action(rec, { phase: 'recording', seconds: 3723 }).label, 'Stop 1:02:03')
    assert.equal(M.action(rec, { phase: 'countdown', seconds: 3 }).label, 'Cancel 3')
    assert.equal(M.action(rec, { phase: 'recording', seconds: 1 }).kind, 'stop')
    assert.deepEqual(M.action(rec, { phase: 'stopping', seconds: 9 }), { kind: 'stop', glyph: 0xF04DB, label: 'Saving…' })
    assert.deepEqual(M.command(rec, { phase: 'stopping', seconds: 9 }, { screenshot: '/s.sh', record: '/r.sh' }), ['/r.sh', 'stop'])
    assert.equal(M.parseOptions({ 'capture-delay': '08' }).delay, 8, 'a zero-padded delay is decimal')
    assert.equal(M.formatElapsed(59), '0:59')
    assert.equal(M.formatElapsed(600), '10:00')

    const scripts = { screenshot: '/s.sh', record: '/r.sh' }
    let s = M.setOption(M.setOption(shot, 'annotate', true).state, 'delay', 3).state
    assert.deepEqual(M.command(s, idle, scripts), ['/s.sh', 'region', '--annotate', '--delay', '3'])
    assert.deepEqual(M.command(shot, idle, scripts), ['/s.sh', 'region'])
    const text = M.initialState({}, 'text')
    assert.deepEqual(M.action(text, idle), { kind: 'capture', glyph: 0xF113D, label: 'Copy text' })
    assert.equal(M.action(text, { phase: 'recording', seconds: 5 }).label, 'Copy text', 'Text works normally while recording')
    assert.deepEqual(M.command(text, idle, scripts), ['/s.sh', 'region', '--text'])
    const textDelayed = M.setOption(M.setOption(text, 'annotate', true).state, 'delay', 5).state
    assert.deepEqual(M.command(textDelayed, idle, scripts), ['/s.sh', 'region', '--text', '--delay', '5'], 'annotate never reaches Text')
    assert.deepEqual(M.command(M.withMode(M.setOption(shot, 'shotTarget', 'window').state, 'text'), idle, scripts), ['/s.sh', 'region', '--text'], 'Text is always a region')
    assert.deepEqual(M.command(rec, idle, scripts), ['/r.sh', 'start', 'screen'])
    assert.deepEqual(M.command(rec, { phase: 'recording', seconds: 1 }, scripts), ['/r.sh', 'stop'])
    assert.deepEqual(M.command(rec, { phase: 'countdown', seconds: 2 }, scripts), ['/r.sh', 'stop'])
}
