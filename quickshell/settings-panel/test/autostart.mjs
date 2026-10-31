import assert from 'node:assert/strict'
import fs from 'node:fs'
// Built, not literal: the doctor's path scan would flag fixture files that do not exist.
const userDir = '~/.config' + '/autostart'
import * as autostart from '../autostart.mjs'

const system = [
    {id: 'nm-applet.desktop', text: '[Desktop Entry]\nType=Application\nName=Network\nExec=nm-applet\nNotShowIn=KDE;GNOME;\nIcon=nm-device-wireless\n'},
    {id: 'blueman.desktop', text: '[Desktop Entry]\nType=Application\nName=Blueman Applet\nExec=blueman-applet\n'},
    {id: 'gnome-only.desktop', text: '[Desktop Entry]\nType=Application\nName=GNOME thing\nExec=gnome-thing\nOnlyShowIn=GNOME;\n'},
    {id: 'skipped.desktop', text: '[Desktop Entry]\nType=Application\nName=Skipped\nExec=skip\nX-systemd-skip=true\n'},
    {id: 'kde.desktop', text: '[Desktop Entry]\nType=Application\nName=KDE thing\nExec=kde-thing\nNotShowIn=Hyprland;\n'},
]
const user = [
    {id: 'blueman.desktop', text: '[Desktop Entry]\nType=Application\nName=Blueman Applet\nHidden=true\n'},
    {id: 'arch-update-tray.desktop', text: '[Desktop Entry]\nType=Application\nName=Arch-Update Systray Applet\nExec=arch-update --tray\n'},
    {id: 'quoted.desktop', text: '[Desktop Entry]\nType=Application\nName=Quoted\nExec="/opt/My App/run" --flag\n'},
    {id: 'gnome-off.desktop', text: '[Desktop Entry]\nType=Application\nName=Gnome off\nExec=blueman-applet\nX-GNOME-Autostart-enabled=false\n'},
]
const onPath = binary => ['nm-applet', 'blueman-applet', 'gnome-thing', 'skip', 'kde-thing', '/opt/My App/run'].includes(binary)
const entries = autostart.autostartEntries({system, user, desktops: ['Hyprland'], onPath})
const byId = Object.fromEntries(entries.map(e => [e.id, e]))

assert.equal(byId['nm-applet.desktop'].origin, 'system')
assert.equal(byId['blueman.desktop'].origin, 'override')
assert.equal(byId['arch-update-tray.desktop'].origin, 'user')
console.log('ok: user files replace system files by id')

assert.equal(byId['nm-applet.desktop'].enabled, true)
assert.equal(byId['nm-applet.desktop'].scope, '')
assert.equal(byId['blueman.desktop'].enabled, false)
assert.equal(byId['gnome-off.desktop'].enabled, true)
assert.equal(byId['gnome-off.desktop'].ignoredGnomeFlag, true)
assert.match(byId['gnome-only.desktop'].scope, /Only for GNOME/)
assert.match(byId['kde.desktop'].scope, /Not for Hyprland/)
assert.match(byId['skipped.desktop'].scope, /systemd/)
console.log('ok: Hidden, ignored GNOME flag, OnlyShowIn, NotShowIn and X-systemd-skip')

assert.equal(byId['blueman.desktop'].name, 'Blueman Applet')
assert.equal(byId['blueman.desktop'].binary, 'blueman-applet')
assert.equal(byId['arch-update-tray.desktop'].installed, false)
assert.equal(byId['arch-update-tray.desktop'].binary, 'arch-update')
assert.equal(byId['quoted.desktop'].binary, '/opt/My App/run')
assert.equal(byId['quoted.desktop'].installed, true)
console.log('ok: overrides describe the system entry; binaries are resolved')

assert.deepEqual(entries.slice(0, 2).map(e => e.id), ['arch-update-tray.desktop', 'gnome-off.desktop'])
console.log('ok: enabled-and-applicable first, then by name')

assert.equal(autostart.unitName('nm-applet.desktop'), 'app-nm\\x2dapplet@autostart.service')
assert.equal(autostart.unitName('org.kde.discover.notifier.desktop'), 'app-org.kde.discover.notifier@autostart.service')
assert.equal(autostart.unitName('a b.desktop'), 'app-a\\x20b@autostart.service')
assert.equal(autostart.unitName('.hidden.desktop'), 'app-\\x2ehidden@autostart.service')
for (const name of ['foo.desktop', 'a b.desktop']) assert.equal(autostart.isAutostartFileName(name), true)
for (const name of ['.foo.desktop', 'foo.desktop~', 'foo.desktop.bak', 'foo.desktop.dpkg-old', 'foo.desktop.rpmsave', 'foo.txt'])
    assert.equal(autostart.isAutostartFileName(name), false, name)
console.log('ok: unit names use systemd escaping')

const units = [
    {unit: 'app-nm\\x2dapplet@autostart.service', active: 'active', sub: 'running'},
    {unit: 'app-gnome\\x2doff@autostart.service', active: 'failed', sub: 'failed'},
    {unit: 'app-quoted@autostart.service', active: 'inactive', sub: 'dead'},
    {unit: 'app-gnome\\x2donly@autostart.service', active: 'inactive', sub: 'dead'},
]
const status = Object.fromEntries(autostart.withStatus(entries, units).map(e => [e.id, e.status]))
assert.deepEqual(status['nm-applet.desktop'], {state: 'running', label: 'Running'})
assert.deepEqual(status['gnome-off.desktop'], {state: 'failed', label: 'Failed'})
assert.deepEqual(status['quoted.desktop'], {state: 'finished', label: 'Finished'})
assert.deepEqual(status['arch-update-tray.desktop'], {state: 'missing', label: 'Not installed: arch-update'})
assert.deepEqual(status['blueman.desktop'], {state: 'none', label: ''})
assert.deepEqual(status['gnome-only.desktop'], {state: 'none', label: ''})
console.log('ok: status from list-units, missing binaries first')

assert.equal(autostart.minimalOverride('Blueman\nApplet'), '[Desktop Entry]\nType=Application\nName=Blueman Applet\nHidden=true\n')
assert.equal(autostart.isMinimalOverride(user[0].text, 'Blueman Applet'), true)
assert.equal(autostart.isMinimalOverride('# note\n\n' + user[0].text, 'Blueman Applet'), true)
assert.equal(autostart.isMinimalOverride(user[0].text + 'Comment=mine\n', 'Blueman Applet'), false)
assert.equal(autostart.isMinimalOverride(user[1].text, 'Arch-Update Systray Applet'), false)
console.log('ok: minimal override text and recognition')

const full = '# keep\n[Desktop Entry]\nName=X\nExec=x\nX-GNOME-Autostart-enabled=false\n\n[Desktop Action new]\nHidden=true\nExec=x --new\n'
const hidden = autostart.setHidden(full, true)
assert.equal(hidden, '# keep\n[Desktop Entry]\nName=X\nExec=x\nX-GNOME-Autostart-enabled=false\nHidden=true\n\n[Desktop Action new]\nHidden=true\nExec=x --new\n')
assert.equal(autostart.setHidden(hidden, false), '# keep\n[Desktop Entry]\nName=X\nExec=x\n\n[Desktop Action new]\nHidden=true\nExec=x --new\n')
assert.equal(autostart.setHidden('[Desktop Entry]\nName=Y\nHidden = true\n', true), '[Desktop Entry]\nName=Y\nHidden=true\n')
assert.equal(autostart.setHidden('[Desktop Entry]\r\nName=Y\r\n', true), '[Desktop Entry]\r\nName=Y\r\nHidden=true\r\n')
assert.throws(() => autostart.setHidden('[Other]\nName=X\n', true), /Not a desktop entry/)
console.log('ok: setHidden edits only the main group and only Hidden / the GNOME flag')

const parsed = autostart.parseEntry('[Desktop Entry]\nName=A\nName=B\n[Other]\nExec=no\n')
assert.deepEqual(parsed, {Name: 'A'})
assert.equal(autostart.parseEntry('[Desktop Entry]\nHidden=true\nHidden=FALSE\nName=A\nName=B\n')['Hidden'], 'FALSE')
const classify = text => autostart.autostartEntries({system: [], user: [{id: 'case.desktop', text: '[Desktop Entry]\n' + text}], desktops: ['Hyprland'], onPath})[0]
assert.equal(classify('Type=Application\nExec=skip\nHidden=True\n').enabled, false)
assert.equal(classify('Type=Application\nExec=skip\nHidden=true\nHidden=FALSE\n').enabled, true)
for (const value of ['1', 'YES', 'y', 'True', 'T', 'ON'])
    assert.equal(classify(`Type=Application\nExec=skip\nHidden=${value}\n`).enabled, false, value)
for (const value of ['0', 'NO', 'n', 'False', 'F', 'OFF'])
    assert.equal(classify(`Type=Application\nExec=skip\nHidden=${value}\n`).enabled, true, value)
assert.match(classify('Type=Application\nExec=skip\nX-systemd-skip=yes\n').scope, /systemd/)
assert.equal(classify('Type=Application\nExec=skip\nX-systemd-skip=yes\nX-systemd-skip=OFF\n').scope, '')
assert.match(classify('Exec=skip\n').scope, /Not an application entry/)
assert.match(classify('Type=Link\nExec=skip\n').scope, /Not an application entry/)
assert.match(classify('Type=Application\nName=X\n').scope, /No command to run/)
assert.equal(classify('Type=Application\nName=X\n').installed, false)
assert.equal(classify('Type=Application\nTryExec=skip\nExec=absent\n').binary, 'absent')
assert.equal(classify('Type=Application\nTryExec=skip\nExec=absent\n').installed, false)
assert.equal(classify('Type=Application\nTryExec=absent\nExec=skip\n').binary, 'absent')
assert.equal(autostart.execBinary({Exec: "'/usr/bin/true' x"}), '/usr/bin/true')
assert.equal(autostart.execBinary({Exec: 'foo"bar baz" --flag'}), 'foobar baz')
console.log('ok: parseEntry keeps the first key and only the main group')

const lua = fs.readFileSync(new URL('../../../hypr/config/setup/autostart.lua', import.meta.url), 'utf8')
const commands = autostart.sessionCommands(lua)
assert.equal(commands[0], '$HOME/.config/scripts/hyprland/respawn.sh waybar')
assert.ok(commands.includes('systemctl --user start …'))
assert.ok(commands.includes('wl-paste --type text --watch cliphist store'))
assert.deepEqual(autostart.sessionCommands('-- hl.exec_cmd("commented")\nhl.exec_cmd("a \\"q\\"")'), ['a "q"'])
assert.deepEqual(autostart.sessionCommands('--[[ hl.exec_cmd("blocked")\n]]\nhl.exec_cmd("live") -- hl.exec_cmd("trailing")'), ['live'])
console.log('ok: session commands parsed from autostart.lua')

{
    // Mixed line endings: every line keeps its own ending and nothing after Hidden= is lost.
    assert.equal(autostart.setHidden('[Desktop Entry]\r\nHidden=true\nName=Keep\nExec=keep --me\n', false), '[Desktop Entry]\r\nName=Keep\nExec=keep --me\n')
    assert.equal(autostart.setHidden('[Desktop Entry]\nName=Keep\nExec=keep\nHidden=true\r\n', false), '[Desktop Entry]\nName=Keep\nExec=keep\n')
    assert.equal(autostart.setHidden('[Desktop Entry]\r\nName=K\r\nExec=k', true), '[Desktop Entry]\r\nName=K\r\nExec=k\r\nHidden=true\r\n')
}
console.log('ok: setHidden keeps mixed line endings intact')

{
    // systemd hides a file it cannot parse: invalid booleans and undefined escapes.
    assert.match(autostart.entryProblem('[Desktop Entry]\nHidden=maybe\n'), /not a boolean/)
    assert.match(autostart.entryProblem('[Desktop Entry]\nX-systemd-skip=perhaps\n'), /not a boolean/)
    assert.match(autostart.entryProblem('[Desktop Entry]\nExec=sh -c "echo \\"hi\\""\n'), /escape/)
    assert.match(autostart.entryProblem('[Desktop Entry]\nExec=sh -c "echo \\$HOME"\n'), /escape/)
    assert.equal(autostart.entryProblem('[Desktop Entry]\nExec=a\\sb\;c\\\\d\nHidden=Yes\n'), '')
    const [bad] = autostart.autostartEntries({system: [], user: [{id: 'bad.desktop', text: '[Desktop Entry]\nType=Application\nName=Bad\nExec=sh -c "echo \\$HOME"\n'}], desktops: ['Hyprland'], onPath: () => true})
    assert.equal(bad.enabled, false)
    assert.match(bad.scope, /Ignored by systemd/)
    assert.equal(autostart.withStatus([bad], [])[0].status.state, 'none')
}
console.log('ok: files systemd cannot parse are reported as ignored, not enabled')

{
    // TryExec is looked up verbatim, never split or unquoted.
    const onPath = binary => ['tool', 'sh', '/opt/My App/run'].includes(binary)
    const entries = autostart.autostartEntries({system: [], user: [
        {id: 'split.desktop', text: '[Desktop Entry]\nType=Application\nName=Split\nExec=tool\nTryExec=tool extra\n'},
        {id: 'spaced.desktop', text: '[Desktop Entry]\nType=Application\nName=Spaced\nExec=sh\nTryExec=/opt/My App/run\n'},
    ], desktops: ['Hyprland'], onPath})
    const byId = Object.fromEntries(entries.map(e => [e.id, e]))
    assert.equal(byId['split.desktop'].installed, false)
    assert.equal(byId['split.desktop'].binary, 'tool extra')
    assert.equal(byId['spaced.desktop'].installed, true)
}
console.log('ok: TryExec is checked verbatim')

{
    // A bad escape in OnlyShowIn/NotShowIn only drops that list; the entry still starts.
    const [entry] = autostart.autostartEntries({system: [], user: [{id: 'x.desktop', text: '[Desktop Entry]\nType=Application\nName=X\nExec=true\nOnlyShowIn=Hypr\\land;\n'}], desktops: ['Hyprland'], onPath: () => true})
    assert.equal(entry.enabled, true)
    assert.equal(entry.scope, '')
    assert.equal(autostart.entryProblem('[Desktop Entry]\nNotShowIn=K\\DE;\n'), '')
}
console.log('ok: a bad escape in a show-in list drops only that list')

{
    // Only the exact canonical form with the masked entry's name is "ours".
    assert.equal(autostart.isMinimalOverride(autostart.minimalOverride('Original'), 'Original'), true)
    assert.equal(autostart.isMinimalOverride('[Desktop Entry]\nName=Custom\nHidden=true\nType=Application\n', 'Custom'), false)
    assert.throws(() => autostart.isMinimalOverride(autostart.minimalOverride('X')), /expected name/)
    assert.equal(autostart.isMinimalOverride(autostart.minimalOverride('Custom'), 'Original'), false)
    assert.equal(autostart.isMinimalOverride(autostart.minimalOverride('Original').replace(/\n/g, '\r\n'), 'Original'), true)
}
console.log('ok: a reordered or renamed override is never treated as the minimal one')

{
    // A later valid show-in list wins over an invalid earlier one.
    const [entry] = autostart.autostartEntries({system: [], user: [{id: 'y.desktop', text: '[Desktop Entry]\nType=Application\nName=Y\nExec=true\nOnlyShowIn=Hypr\\land;\nOnlyShowIn=GNOME;\n'}], desktops: ['Hyprland'], onPath: () => true})
    assert.match(entry.scope, /Only for GNOME/)
    // More keys whose bad escape hides the whole file.
    for (const key of ['AutostartCondition', 'X-KDE-autostart-condition', 'X-GNOME-Autostart-Phase'])
        assert.match(autostart.entryProblem(`[Desktop Entry]\n${key}=foo\\q\n`), /escape/)
    // A nameless system entry: the override must carry the id-based name to count as ours.
    const sys = '[Desktop Entry]\nType=Application\nExec=/usr/bin/true\n'
    assert.equal(autostart.overrideName('nameless.desktop', sys), 'nameless')
    assert.equal(autostart.isMinimalOverride(autostart.minimalOverride('Personal choice'), autostart.overrideName('nameless.desktop', sys)), false)
    const [masked] = autostart.autostartEntries({system: [{id: 'nameless.desktop', text: sys}], user: [{id: 'nameless.desktop', text: autostart.minimalOverride('Personal choice')}], desktops: ['Hyprland'], onPath: () => true})
    // Its Name says nothing about the entry: describe the system file, and flag the override as stale.
    assert.equal(masked.name, 'nameless')
    assert.equal(masked.staleOverride, true)
}
console.log('ok: later show-in lists, condition keys and nameless system entries')

{
    // A canonical Hidden override whose Name no longer matches: described by the system file it masks.
    const sys = '[Desktop Entry]\nType=Application\nName=New Name\nExec=tool --flag\n'
    const files = {system: [{id: 'r.desktop', text: sys}, {id: 'ok.desktop', text: sys}], desktops: ['Hyprland'], onPath: () => true}
    const [stale, exact] = ['r.desktop', 'ok.desktop'].map(id => autostart.autostartEntries(Object.assign({}, files, {user: [{id, text: autostart.minimalOverride(id === 'r.desktop' ? 'Old Name' : 'New Name')}]})).find(e => e.id === id))
    assert.deepEqual([stale.name, stale.binary, stale.scope, stale.enabled, stale.origin, stale.staleOverride, stale.removable], ['New Name', 'tool', '', false, 'override', true, true])
    assert.deepEqual([exact.name, exact.staleOverride, exact.removable], ['New Name', false, false])
    assert.equal(autostart.withStatus([stale], [])[0].status.label, 'Hidden by ' + userDir + '/r.desktop')
    assert.equal(autostart.withStatus([exact], [])[0].status.label, '')
    assert.equal(autostart.isMinimalShape(autostart.minimalOverride('Whatever')), true)
    assert.equal(autostart.isMinimalShape(autostart.minimalOverride('Whatever') + 'Exec=x\n'), false)
}
console.log('ok: a renamed minimal override is described by the system file and offered for removal')

{
    // An unreadable or dangling user file still masks the system entry; a link is flagged.
    const sys = [{id: 'm.desktop', text: '[Desktop Entry]\nType=Application\nName=Masked\nExec=tool\n'}]
    const list = autostart.autostartEntries({system: sys, user: [{id: 'm.desktop', text: undefined, link: true}, {id: 'only.desktop', text: undefined, link: false}, {id: 'l.desktop', text: '[Desktop Entry]\nType=Application\nName=L\nExec=tool\n', link: true}], desktops: ['Hyprland'], onPath: () => true})
    const byId = Object.fromEntries(list.map(e => [e.id, e]))
    assert.deepEqual([byId['m.desktop'].origin, byId['m.desktop'].scope, byId['m.desktop'].name, byId['m.desktop'].link, byId['m.desktop'].enabled], ['override', autostart.unreadableScope, 'Masked', true, false])
    assert.deepEqual([byId['only.desktop'].origin, byId['only.desktop'].scope, byId['only.desktop'].name, byId['only.desktop'].removable], ['user', autostart.unreadableScope, 'only', true])
    assert.deepEqual([byId['l.desktop'].link, byId['l.desktop'].scope, byId['l.desktop'].origin], [true, '', 'user'])
    assert.equal(autostart.withStatus([byId['m.desktop']], [])[0].status.state, 'none')
}
console.log('ok: unreadable user files mask the system entry and links are flagged')

{
    assert.equal(autostart.appScope({Exec: 'tool %u'}, ['Hyprland']), '')
    assert.match(autostart.appScope({}, ['Hyprland']), /No command to run/)
    assert.match(autostart.appScope({Exec: 'tool', OnlyShowIn: 'KDE;'}, ['Hyprland']), /Only for KDE/)
    assert.match(autostart.appScope({Exec: 'tool', NotShowIn: 'Hyprland;'}, ['Sway', 'Hyprland']), /Not for Hyprland/)
}
console.log('ok: appScope applies the generator rules to an installed application')

{
    const env = autostart.parseEnvironment("A=plain\nPATH=$'/opt/it\\'s/bin:/usr/bin'\nX=$'tab\\there\\nnew\\\\slash \\x41\\x7a \\xc3\\xa9'\nEMPTY=\nBROKEN=$'\nnoequals\n")
    assert.equal(env.A, 'plain')
    assert.equal(env.PATH, "/opt/it's/bin:/usr/bin")
    assert.equal(env.X, 'tab\there\nnew\\slash Az é')
    assert.equal(env.EMPTY, '')
    assert.equal(env.BROKEN, "$'")
}
console.log("ok: show-environment $'...' quoting is undone")

{
    // A customised override is never removable; a broken one names its file.
    const sys = [{id: 'nm-applet.desktop', text: '[Desktop Entry]\nType=Application\nName=Network\nExec=nm-applet\n'}]
    const [custom] = autostart.autostartEntries({system: sys, user: [{id: 'nm-applet.desktop', text: '[Desktop Entry]\nType=Application\nName=Network\nExec=nm-applet --indicator\n'}], desktops: ['Hyprland'], onPath: () => true})
    assert.equal(custom.removable, false)
    const [broken] = autostart.autostartEntries({system: sys, user: [{id: 'nm-applet.desktop', text: '[Desktop Entry]\nType=Application\nName=Network\nComment=mine\nHidden=true\n'}], desktops: ['Hyprland'], onPath: () => true})
    assert.equal(broken.scope, userDir + '/nm-applet.desktop: No command to run')
    assert.equal(broken.removable, false)
    const [stale] = autostart.autostartEntries({system: sys, user: [{id: 'nm-applet.desktop', text: autostart.minimalOverride('Old name')}], desktops: ['Hyprland'], onPath: () => true})
    assert.equal(stale.removable, true)
    assert.equal(stale.scope, '')
}
console.log('ok: customised overrides are not removable; a broken override names its file')

{
    // Unreadable files: removable only when they add an app, never when they mask a system entry.
    const sys = [{id: 'x.desktop', text: '[Desktop Entry]\nType=Application\nName=X\nExec=true\n'}]
    const [masking] = autostart.autostartEntries({system: sys, user: [{id: 'x.desktop', text: undefined, link: false}], desktops: ['Hyprland'], onPath: () => true})
    assert.equal(masking.origin, 'override')
    assert.equal(masking.removable, false)
    const [alone] = autostart.autostartEntries({system: [], user: [{id: 'y.desktop', text: undefined, link: false}], desktops: ['Hyprland'], onPath: () => true})
    assert.equal(alone.removable, true)
}
console.log('ok: an unreadable override is never offered for removal')
