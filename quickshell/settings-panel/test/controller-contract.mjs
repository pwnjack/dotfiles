import assert from 'node:assert/strict'
import fs from 'node:fs'

// The QML tests drive the views with a fake controller, so a method a view calls on the real
// one (shell.qml) can be missing without any of them noticing. Every `controller.method(` a
// view calls must be a function shell.qml defines.
const dir = new URL('../', import.meta.url)
const shell = fs.readFileSync(new URL('shell.qml', dir), 'utf8')
const defined = new Set([...shell.matchAll(/^\s*function (\w+)\(/gm)].map(match => match[1]))
const views = fs.readdirSync(dir).filter(name => name.endsWith('.qml') && name !== 'shell.qml')
let calls = 0
for (const view of views) {
    const source = fs.readFileSync(new URL(view, dir), 'utf8')
    for (const [, method] of source.matchAll(/\bcontroller\.(\w+)\(/g)) {
        calls++
        assert.ok(defined.has(method), `${view} calls controller.${method}() but shell.qml defines no such function`)
    }
}
assert.ok(calls > 0 && defined.has('soundRequest'), 'the scan found the views\' controller calls')
console.log('ok: every controller method a view calls exists in shell.qml')
