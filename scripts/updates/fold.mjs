// Folds the runner's log (stdin) into state.json, which the update card and
// Waybar's custom/updates read. The parsing is quickshell/updates/model.mjs,
// the same code the card imports, so the two can never disagree.
//
// Usage: node fold.mjs <state.json> <startedAt epoch seconds>
// UPDATES_SIGNAL=none disables the Waybar refresh signal (tests).
import { createInterface } from 'node:readline'
import { writeFileSync, renameSync } from 'node:fs'
import { spawn } from 'node:child_process'
import * as model from '../../quickshell/updates/model.mjs'

const [statePath, startedArg] = process.argv.slice(2)
if (!statePath) {
    console.error('usage: fold.mjs STATE_JSON STARTED_AT')
    process.exit(2)
}
const signalWaybar = process.env.UPDATES_SIGNAL !== 'none'
let state = model.initialState(Number(startedArg) || Math.floor(Date.now() / 1000))
let written = ''
let writtenAt = 0
let timer = null
let signalled = { status: '', pct: -1, at: 0 }

// Rename makes every read see a whole file, never a half-written one.
function write() {
    timer = null
    const snap = model.snapshot(state)
    const json = JSON.stringify(snap)
    if (json !== written) {
        writeFileSync(`${statePath}.tmp`, `${json}\n`)
        renameSync(`${statePath}.tmp`, statePath)
        written = json
        writtenAt = Date.now()
    }
    // Waybar re-runs updates.sh on signal 9. Status changes always signal;
    // percentage changes at most once a second.
    const pct = Math.floor(snap.progress * 100)
    const now = Date.now()
    if (signalWaybar && (snap.status !== signalled.status || (pct !== signalled.pct && now - signalled.at >= 1000))) {
        spawn('pkill', ['-x', '-RTMIN+9', 'waybar'], { stdio: 'ignore' }).on('error', () => {})
        signalled = { status: snap.status, pct, at: now }
    }
}

// At most one write per 150 ms; the card polls every 120 ms and glides.
function schedule() {
    if (timer) return
    timer = setTimeout(write, Math.max(0, 150 - (Date.now() - writtenAt)))
}

write()
const lines = createInterface({ input: process.stdin })
lines.on('line', line => {
    state = model.foldLine(state, line, Date.now())
    schedule()
})
lines.on('close', () => {
    // A runner that died mid-stream must not leave "running" behind forever.
    if (!state.ended) state = model.foldLine(state, '@@end', Date.now())
    if (timer) clearTimeout(timer)
    write()
})
