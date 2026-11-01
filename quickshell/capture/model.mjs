// The capture strip's pure model (docs/capture.md). Everything the
// strip decides lives here: the option files behind its controls, which
// controls each mode shows, the keyboard, the action button and the command
// it runs. shell.qml and Strip.qml only draw it; test/model.mjs runs it under node.

// Qt's V4 engine (QML imports this file) has no object spread: Object.assign.
export const MODES = ['screenshot', 'text', 'record']
export const TARGETS = ['screen', 'window', 'region']
export const DELAYS = [0, 3, 5, 10]

// State key -> option file under options/. The scripts read the same files:
// record.sh capture-delay, capture-audio, capture-mic and capture-rec-target;
// screenshot.sh capture-freeze.
export const FILES = {
    shotTarget: 'capture-shot-target',
    recTarget: 'capture-rec-target',
    delay: 'capture-delay',
    freeze: 'capture-freeze',
    annotate: 'capture-annotate',
    audio: 'capture-audio',
    mic: 'capture-mic',
}
const DEFAULTS = { shotTarget: 'region', recTarget: 'screen', delay: 0, freeze: false, annotate: false, audio: false, mic: false }

// texts: { 'capture-…': file text | undefined }. A missing or invalid file is
// the default; a whole-number delay is shown as written (record.sh accepts it too).
export function parseOptions(texts) {
    const read = key => String(texts[FILES[key]] ?? '').trim()
    const target = key => TARGETS.includes(read(key)) ? read(key) : DEFAULTS[key]
    const flag = key => read(key) === 'true'
    const delayText = read('delay')
    return {
        shotTarget: target('shotTarget'),
        recTarget: target('recTarget'),
        delay: /^\d+$/.test(delayText) ? parseInt(delayText, 10) : DEFAULTS.delay,
        freeze: flag('freeze'),
        annotate: flag('annotate'),
        audio: flag('audio'),
        mic: flag('mic'),
    }
}

export function initialState(texts, mode) {
    return Object.assign({ mode: MODES.includes(mode) ? mode : 'screenshot' }, parseOptions(texts))
}

export function withMode(state, mode) {
    return MODES.includes(mode) ? Object.assign({}, state, { mode }) : state
}

export const targetKey = mode => mode === 'record' ? 'recTarget' : 'shotTarget'

// Text has no target (it is always a dragged region) and no annotate.
export function controls(mode) {
    if (mode === 'record') return ['delay', 'audio', 'mic']
    return mode === 'text' ? ['delay', 'freeze'] : ['delay', 'freeze', 'annotate']
}

export const nextDelay = d => DELAYS.find(x => x > d) ?? 0
export const delayLabel = d => d ? `${d}s` : 'Off'

// -> { state, write: [file, text] | null }; a write only when the value changed.
export function setOption(state, key, value) {
    if (state[key] === value) return { state, write: null }
    return { state: Object.assign({}, state, { [key]: value }), write: [FILES[key], String(value)] }
}

// The tab one step along MODES, wrapping round.
export const cycleMode = (mode, step) => MODES[(MODES.indexOf(mode) + step + MODES.length) % MODES.length]

// name: Tab | Backtab | Left | Right | Return | Escape (shell.qml maps Qt keys to these).
// -> { state, write, effect: none | run | close }
export function reduceKey(state, name) {
    const same = { state, write: null, effect: 'none' }
    switch (name) {
    case 'Tab':
    case 'Backtab':
        return Object.assign({}, same, { state: withMode(state, cycleMode(state.mode, name === 'Tab' ? 1 : -1)) })
    case 'Left':
    case 'Right': {
        if (state.mode === 'text') return same
        const key = targetKey(state.mode)
        const i = TARGETS.indexOf(state[key]) + (name === 'Left' ? -1 : 1)
        if (i < 0 || i >= TARGETS.length) return same
        return Object.assign({}, setOption(state, key, TARGETS[i]), { effect: 'none' })
    }
    case 'Return':
        return Object.assign({}, same, { effect: 'run' })
    case 'Escape':
        return Object.assign({}, same, { effect: 'close' })
    default:
        return same
    }
}

// m:ss, or h:mm:ss from an hour on; record.sh's fmt agrees.
export function formatElapsed(s) {
    const pad = n => String(n).padStart(2, '0')
    if (s >= 3600) return `${Math.floor(s / 3600)}:${pad(Math.floor(s % 3600 / 60))}:${pad(s % 60)}`
    return `${Math.floor(s / 60)}:${pad(s % 60)}`
}

// record.sh status --json -> { phase, seconds }; anything unreadable is idle.
export function parseStatus(text) {
    try {
        const j = JSON.parse(text)
        const phase = ['countdown', 'recording', 'stopping'].includes(j.phase) ? j.phase : 'idle'
        return { phase, seconds: phase === 'idle' ? 0 : Math.max(0, Number(j.seconds) || 0) }
    } catch (e) {
        return { phase: 'idle', seconds: 0 }
    }
}

// The action button. kind picks the colour: capture = accent, record/stop = red.
export function action(state, status) {
    if (state.mode === 'text') return { kind: 'capture', glyph: 0xF113D, label: 'Copy text' }
    if (state.mode !== 'record') return { kind: 'capture', glyph: 0xF0100, label: 'Capture' }
    if (status.phase === 'stopping') return { kind: 'stop', glyph: 0xF04DB, label: 'Saving…' }
    if (status.phase === 'countdown') return { kind: 'stop', glyph: 0xF04DB, label: `Cancel ${status.seconds}` }
    if (status.phase !== 'idle') return { kind: 'stop', glyph: 0xF04DB, label: `Stop ${formatElapsed(status.seconds)}` }
    return { kind: 'record', glyph: 0xF044A, label: 'Record' }
}

// The widest label action() normally produces at the 1:1 size, for a fixed
// button width. A recording past 10 h or a 6-digit hand-written delay elides
// the label; the width stays fixed.
export const WIDEST_ACTION_LABEL = 'Stop 9:59:59'

// The argv the action runs, started detached by shell.qml once the strip is gone.
export function command(state, status, scripts) {
    if (state.mode === 'text') {
        const argv = [scripts.screenshot, 'region', '--text']
        if (state.delay) argv.push('--delay', String(state.delay))
        return argv
    }
    if (state.mode !== 'record') {
        const argv = [scripts.screenshot, state.shotTarget]
        if (state.annotate) argv.push('--annotate')
        if (state.delay) argv.push('--delay', String(state.delay))
        return argv
    }
    if (status.phase !== 'idle') return [scripts.record, 'stop']
    return [scripts.record, 'start', state.recTarget]
}
