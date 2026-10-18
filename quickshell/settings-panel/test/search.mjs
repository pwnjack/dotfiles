import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'

// The QML tests stub visibleRows with their own filter, so the real binding in
// shell.qml is evaluated here, against the real catalog.
const catalog = JSON.parse(fs.readFileSync(new URL('../catalog.json', import.meta.url)))
const source = fs.readFileSync(new URL('../shell.qml', import.meta.url), 'utf8')
const start = 'readonly property var visibleRows: {'
const body = source.slice(source.indexOf(start) + start.length, source.indexOf('\n    function refresh()'))
const visible = (query, category = 'appearance') =>
    vm.runInNewContext('(function () {' + body.slice(0, body.lastIndexOf('}')) + '})()', {catalog, query, category}).map(row => row.id)

// A page lists its own rows, minus those its view draws itself.
assert.equal(visible('').length, catalog.rows.filter(row => row.category === 'appearance').length)
assert.deepEqual(visible('', 'network'), [])
// Search matches section titles, and the plainer titles kept their old search terms.
for (const [query, id] of [['night light', 'power.nightlight-start'], ['output', 'sound.output-port'],
    ['window opening', 'anim.windowsIn'], ['windows move', 'anim.windowsMove'], ['recording volume', 'sound.input-port'],
    ['volume', 'sound.output-port'], ['speakers', 'sound.output-port'], ['mic', 'sound.input-port'],
    ['palette', 'appearance.theme-scheme'], ['matugen', 'appearance.theme-contrast'],
    ['source colour', 'appearance.theme-prefer'], ['colors', 'appearance.theme-scheme'],
    ['scroll factor', 'input.scroll-factor'], ['vrr', 'monitors.vrr'], ['numlock', 'input.numlock']])
    assert.ok(visible(query).includes(id), `"${query}" finds ${id}`)
// The titles the panel shipped with before rows were renamed (October 2, 2026), parentheses
// dropped: people search the wording they already know, so each must still find its row.
const previousTitles = [
    ["Blur", "appearance.blur"], ["Blur Size", "appearance.blur-size"], ["Blur Passes", "appearance.blur-passes"],
    ["Shadows", "appearance.shadows"], ["Corner Rounding", "appearance.rounding"],
    ["Border Width", "appearance.border"], ["Gaps Inner", "appearance.gaps-in"],
    ["Gaps Outer", "appearance.gaps-out"], ["Active Opacity", "appearance.opacity-active"],
    ["Inactive Opacity", "appearance.opacity-inactive"], ["Main Font", "appearance.font"],
    ["GTK Font", "appearance.font-gtk"], ["Colour Scheme", "appearance.color-scheme"],
    ["GTK Theme", "appearance.gtk-theme"], ["Icon Theme", "appearance.icon-theme"],
    ["Qt Theme Kvantum", "appearance.kvantum"], ["Cursor Theme", "appearance.cursor-theme"],
    ["Cursor Size", "appearance.cursor-size"], ["CPU", "bar.cpu"], ["Memory", "bar.memory"], ["GPU", "bar.gpu"],
    ["Disk", "bar.disk"], ["Network", "bar.network"], ["Updates", "bar.updates"], ["Position", "bar.position"],
    ["Style", "bar.style"], ["Background opacity", "bar.opacity"], ["Border", "bar.border"],
    ["Monitors", "bar.output"], ["Clock seconds", "bar.clock-seconds"], ["Workspaces", "bar.workspaces"],
    ["Animations", "anim.master"], ["Windows", "anim.windows"], ["Windows In", "anim.windowsIn"],
    ["Windows Out", "anim.windowsOut"], ["Windows Move", "anim.windowsMove"], ["Fade", "anim.fade"],
    ["Workspaces", "anim.workspaces"], ["Border", "anim.border"], ["Layout Mode", "win.layout"],
    ["Preserve Split", "win.preserve-split"], ["Smart Split", "win.smart-split"], ["Allow Tearing", "win.tearing"],
    ["Resize on Border", "win.resize-border"], ["XWayland", "win.xwayland"],
    ["Dim Inactive Windows", "win.dim-inactive"], ["Dim Strength", "win.dim-strength"],
    ["Focus on Activation", "win.focus-on-activate"], ["Mouse Sensitivity", "input.sensitivity"],
    ["Focus Follows Mouse", "input.follow-mouse"], ["Numlock by Default", "input.numlock"],
    ["Natural Scroll Touchpad", "input.natural-scroll"], ["Touchpad Scroll Factor", "input.scroll-factor"],
    ["Keyboard Layout", "input.kb-layout"], ["Layout Variant", "input.kb-variant"],
    ["Keyboard Options", "input.kb-options"], ["Key Repeat Rate", "input.repeat-rate"],
    ["Key Repeat Delay", "input.repeat-delay"], ["Pointer Acceleration", "input.accel-profile"],
    ["Left-Handed Mouse", "input.left-handed"], ["Tap to Click Touchpad", "input.tap-to-click"],
    ["Disable Touchpad While Typing", "input.dwt"], ["Hide Idle Cursor", "input.hide-cursor"],
    ["Keep Cursor in Place", "input.no-warps"], ["Screen Zoom", "a11y.zoom"], ["Text Size", "a11y.text-scale"],
    ["Output Device", "sound.output-port"], ["Output Port", "sound.output-port"],
    ["Output Profile", "sound.output-profile"], ["Input Device", "sound.input-port"], ["Input Port", "sound.input-port"],
    ["Microphone Level", "sound.input-port"], ["Wi-Fi", "network.wifi"], ["Default Timeout", "notif.timeout"],
    ["Low Priority Timeout", "notif.timeout-low"], ["Notification Width", "notif.width"],
    ["Control Center Width", "notif.cc-width"], ["Transition Time", "notif.transition"],
    ["Position X", "notif.pos-x"], ["Position Y", "notif.pos-y"], ["VRR Adaptive Sync", "monitors.vrr"],
    ["Lock Timeout", "power.lock"], ["Screen Off Timeout", "power.dpms"], ["Power Profile", "power.profile"],
    ["Suspend After", "power.suspend"], ["Wake on Key Press", "power.dpms-key"],
    ["Wake on Mouse Move", "power.dpms-mouse"], ["Night Light Warmth", "power.nightlight-temp"],
    ["Night Light Starts", "power.nightlight-start"], ["Night Light Ends", "power.nightlight-end"],
    ["Time Zone", "region.timezone"], ["Set Time Automatically", "region.ntp"], ["Clock Format", "region.clock"],
    ["Language", "region.language"], ["Formats", "region.formats"], ["Lock on Autologin", "startup.autologin"],
    ["Proton VPN Auto-connect", "startup.protonvpn"], ["Random Wallpaper", "startup.randomwallpaper"],
    ["Browser", "apps.browser"], ["Terminal", "apps.terminal"], ["TUI Editor", "apps.editor"],
    ["Code Editor", "apps.codeeditor"], ["File Manager", "apps.filemanager"], ["Update Command", "apps.aurhelper"],
    ["Launcher Style", "apps.launcher"], ["Folders", "mime.folders"], ["Web Links", "mime.web"],
    ["PDF Documents", "mime.pdf"], ["Images", "mime.images"], ["Video", "mime.video"], ["Audio", "mime.audio"],
    ["Text Files", "mime.text"], ["Archives", "mime.archives"], ["Email Links", "mime.email"]
]
for (const [title, id] of previousTitles) assert.ok(visible(title).includes(id), `"${title}" finds ${id}`)
console.log('ok: search')
