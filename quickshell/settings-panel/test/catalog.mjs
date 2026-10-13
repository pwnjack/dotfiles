import assert from 'node:assert/strict'
import fs from 'node:fs'
import * as pages from '../pages.mjs'

const catalog = JSON.parse(fs.readFileSync(new URL('../catalog.json', import.meta.url)))
assert.deepEqual(pages.validateCatalog(catalog), [])
// Appearance leads: it is the page the panel opens on, so the panel opens at the top of the list.
assert.deepEqual(catalog.categories.map(c => c.id), ['appearance', 'bar', 'windows', 'animations', 'notifications',
    'network', 'devices', 'monitors', 'sound', 'power', 'input', 'accessibility', 'region', 'calendar', 'startup', 'apps', 'about'])
// Row ids are API: requests, live tags and saved overrides name them. A re-home never renames one.
assert.deepEqual(catalog.rows.map(row => row.id).sort(), ["a11y.text-scale", "a11y.zoom", "anim.border", "anim.fade",
    "anim.master", "anim.windows", "anim.windowsIn", "anim.windowsMove", "anim.windowsOut", "anim.workspaces",
    "appearance.blur", "appearance.blur-passes", "appearance.blur-size", "appearance.border", "appearance.color-scheme",
    "appearance.cursor-size", "appearance.cursor-theme", "appearance.desktop-clock", "appearance.desktop-clock-font", "appearance.font", "appearance.font-gtk", "appearance.gaps-in",
    "appearance.gaps-out", "appearance.gtk-theme", "appearance.icon-theme", "appearance.kvantum",
    "appearance.opacity-active", "appearance.opacity-inactive", "appearance.rounding", "appearance.shadows",
    "apps.aurhelper", "apps.browser", "apps.codeeditor", "apps.editor", "apps.filemanager", "apps.launcher",
    "apps.terminal", "bar.agenda", "bar.border", "bar.clock-seconds", "bar.cpu", "bar.disk", "bar.gpu", "bar.memory", "bar.network",
    "bar.opacity", "bar.output", "bar.position", "bar.style", "bar.updates", "bar.workspaces",
    "calendar.alert", "calendar.declined", "calendar.default", "calendar.duration", "input.accel-profile",
    "input.dwt", "input.follow-mouse", "input.hide-cursor", "input.kb-layout", "input.kb-options", "input.kb-variant",
    "input.left-handed", "input.natural-scroll", "input.no-warps", "input.numlock", "input.repeat-delay",
    "input.repeat-rate", "input.scroll-factor", "input.sensitivity", "input.tap-to-click", "mime.archives", "mime.audio",
    "mime.email", "mime.folders", "mime.images", "mime.pdf", "mime.text", "mime.video", "mime.web", "monitors.vrr",
    "network.wifi", "notif.cc-width", "notif.pos-x", "notif.pos-y", "notif.timeout", "notif.timeout-low",
    "notif.transition", "notif.width", "power.dpms", "power.dpms-key", "power.dpms-mouse", "power.lock",
    "power.nightlight-end", "power.nightlight-start", "power.nightlight-temp", "power.profile", "power.suspend",
    "region.clock", "region.formats", "region.language", "region.ntp", "region.timezone", "sound.input",
    "sound.input-port", "sound.mic-level", "sound.output", "sound.output-port", "sound.output-profile",
    "startup.autologin", "startup.protonvpn", "startup.randomwallpaper", "win.dim-inactive", "win.dim-strength",
    "win.focus-on-activate", "win.layout", "win.preserve-split", "win.resize-border", "win.smart-split", "win.tearing",
    "win.xwayland"])
// Hyprland animation speeds are durations: their sliders are mirrored so right means faster.
for (const row of catalog.rows.filter(row => row.category === 'animations' && row.kind === 'slider')) {
    assert.equal(row.invert, true, row.id)
    assert.deepEqual(row.ends, ['Slow', 'Fast'], row.id)
    assert.equal(row.dependsOn, 'anim.master', row.id)
}
console.log('ok: catalog structure')
