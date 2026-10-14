import assert from 'node:assert/strict'
import fs from 'node:fs'

// Compare the UI's pre-generation colours with the shared loader's actual defaults.
const source = relative => fs.readFileSync(new URL(relative, import.meta.url), 'utf8')
const palette = source('../../../scripts/theming/palette.sh')
const slots = palette.match(/_WAL_FALLBACK=\(([\s\S]*?)\n\)/)[1].match(/#[0-9a-f]{6}/g)
const roles = Object.fromEntries([...palette.match(/_ROLE_FALLBACK=\(([\s\S]*?)\n\)/)[1]
    .matchAll(/([a-z0-9_]+)=(#[0-9a-f]{6})/g)].map(match => [match[1], match[2]]))
assert.equal(slots[0], roles.surface)
assert.equal(slots[7], roles.on_surface)
const shell = source('../shell.qml')
for (const [setting, role] of [
    ['BACKGROUND','surface'], ['FOREGROUND','on_surface'], ['ACCENT','primary'],
    ['ON_ACCENT','on_primary'], ['ERROR','error'],
]) {
    const fallback = shell.match(new RegExp(`Quickshell\\.env\\("SETTINGS_${setting}"\\)\\s*\\|\\|\\s*"(#[0-9a-f]{6})"`))
    assert.ok(fallback, `SETTINGS_${setting} has an explicit fallback`)
    assert.equal(fallback[1], roles[role], `SETTINGS_${setting} matches ${role}`)
}
const viewError = source('../SettingsView.qml').match(/readonly property color warn:\s*controller\.errorColor\s*\|\|\s*"(#[0-9a-f]{6})"/)
assert.ok(viewError, 'alerts use the supplied semantic error colour with a fallback')
assert.equal(viewError[1], roles.error)
const launcher = source('../../../scripts/hyprland/settings-panel.sh')
assert.match(launcher, /^export SETTINGS_ERROR(?:=|\s*$)/m)
assert.match(launcher, /^(?:export )?SETTINGS_ERROR=\$\(wal_role error\)$/m)
console.log('ok: panel fallbacks match matugen slots and roles; launcher exports the semantic error colour')
