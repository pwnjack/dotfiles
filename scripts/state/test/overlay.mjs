import assert from 'node:assert/strict'
import * as O from '../overlay.mjs'

const map = obj => new Map(Object.entries(obj))
const ini = (section, key) => `${section}\t${key}`

assert.equal(O.formatFor('options'), 'dir')
assert.equal(O.formatFor('swaync/config.json'), 'json')
assert.equal(O.formatFor('hypr/hyprsunset.conf'), 'hyprvars')
assert.equal(O.formatFor('gtk-3.0/settings.ini'), 'ini')
assert.equal(O.formatFor('mimeapps.list'), 'ini')
console.log('ok: formats follow the path')

// dir: a live edit becomes an override; deleting a key file resets it.
{
    const defaults = map({ browser: 'zen\n', editor: 'nvim\n' })
    let h = O.harvest('dir', { defaults, last: defaults, live: map({ browser: 'firefox\n', editor: 'nvim\n' }), overrides: new Map(), removed: new Set() })
    assert.deepEqual([...h.overrides], [['browser', 'firefox\n']])
    const rendered = O.effective(defaults, h.overrides, h.removed)
    h = O.harvest('dir', { defaults, last: rendered, live: map({ editor: 'nvim\n' }), overrides: h.overrides, removed: h.removed })
    assert.equal(h.overrides.size, 0, 'deleting options/browser resets it')
    assert.equal(h.removed.size, 0)
}
console.log('ok: dir harvest and reset')

// No last record: compare with defaults (adoption). Override-only keys survive.
{
    const defaults = map({ browser: 'zen\n' })
    const h = O.harvest('dir', { defaults, last: null, live: map({ browser: 'zen\n', 'capture-delay': '3\n' }), overrides: new Map(), removed: new Set() })
    assert.deepEqual([...h.overrides], [['capture-delay', '3\n']])
}
console.log('ok: adoption without a last record')

// A default changed in the repo reaches an unchanged key, not an overridden one.
{
    const old = map({ browser: 'zen\n', editor: 'nvim\n' })
    const overrides = map({ browser: 'firefox\n' })
    const last = O.effective(old, overrides, new Set())
    const next = map({ browser: 'chromium\n', editor: 'helix\n' })
    const h = O.harvest('dir', { defaults: next, last, live: last, overrides, removed: new Set() })
    assert.deepEqual([...O.effective(next, h.overrides, h.removed)], [['browser', 'firefox\n'], ['editor', 'helix\n']])
}
console.log('ok: new defaults reach keys without an override')

// An override equal to its default is dropped.
{
    const defaults = map({ browser: 'zen\n' })
    const h = O.harvest('dir', { defaults, last: map({ browser: 'firefox\n' }), live: map({ browser: 'zen\n' }), overrides: map({ browser: 'firefox\n' }), removed: new Set() })
    assert.equal(h.overrides.size, 0)
}
console.log('ok: overrides equal to the default are dropped')

// ini: removal recorded, reappearance clears it, unknown keys kept.
{
    const text = '# GTK\n[Settings]\ngtk-theme-name=Kripton\ngtk-font-name=Sans 11\n\n[Other]\nx=1\n'
    const defaults = O.parse('ini', text)
    const live = O.parse('ini', '[Settings]\ngtk-theme-name=Adwaita\ngtk-cursor-theme-size=24\n\n[Other]\nx=1\n')
    let h = O.harvest('ini', { defaults, last: defaults, live, overrides: new Map(), removed: new Set() })
    assert.deepEqual([...h.overrides], [[ini('Settings', 'gtk-theme-name'), 'Adwaita'], [ini('Settings', 'gtk-cursor-theme-size'), '24']])
    assert.deepEqual([...h.removed], [ini('Settings', 'gtk-font-name')])
    const out = O.layout('ini', text, O.effective(defaults, h.overrides, h.removed))
    assert.equal(out, '# GTK\n[Settings]\ngtk-theme-name=Adwaita\ngtk-cursor-theme-size=24\n\n[Other]\nx=1\n')
    const back = O.parse('ini', out + '')
    const live2 = new Map(back); live2.set(ini('Settings', 'gtk-font-name'), 'Sans 11')
    h = O.harvest('ini', { defaults, last: back, live: live2, overrides: h.overrides, removed: h.removed })
    assert.equal(h.removed.size, 0, 'a key that reappears is no longer removed')
}
console.log('ok: ini removals, reappearance and layout')

// ini: a new section is appended; keys before any header stay in section "".
{
    const text = '[Default Applications]\ntext/plain=nvim.desktop\n'
    const defaults = O.parse('ini', text)
    const entries = O.effective(defaults, map({ [ini('Added Associations', 'image/png')]: 'mpv.desktop;' }), new Set())
    assert.equal(O.layout('ini', text, entries), '[Default Applications]\ntext/plain=nvim.desktop\n\n[Added Associations]\nimage/png=mpv.desktop;\n')
}
console.log('ok: ini new sections')

assert.throws(() => O.parse('ini', '[Settings]\nnot a pair\n'), /line 2/)
assert.throws(() => O.parse('json', '[1,2]'), /JSON object/)
console.log('ok: malformed live files are rejected')

// json: top-level keys, defaults order first.
{
    const text = '{\n  "timeout": 5,\n  "widgets": ["a"]\n}\n'
    const defaults = O.parse('json', text)
    const live = O.parse('json', '{"widgets":["a"],"timeout":9,"extra":true}')
    const h = O.harvest('json', { defaults, last: defaults, live, overrides: new Map(), removed: new Set() })
    assert.equal(O.layout('json', text, O.effective(defaults, h.overrides, h.removed)), '{\n  "timeout": 9,\n  "widgets": [\n    "a"\n  ],\n  "extra": true\n}\n')
    assert.equal(O.serialize('json', h.overrides), '{\n  "timeout": 9,\n  "extra": true\n}\n')
}
console.log('ok: json overlay')

// hyprvars: only $var lines are keys; everything else is fixed text.
{
    const text = '# schedule\n$night_temp = 4000\nprofile {\n    temperature = $night_temp\n}\n'
    const defaults = O.parse('hyprvars', text)
    const live = O.parse('hyprvars', '$night_temp = 3500\n$stray = 1\n')
    const h = O.harvest('hyprvars', { defaults, last: defaults, live, overrides: new Map(), removed: new Set() })
    assert.deepEqual([...h.overrides], [['night_temp', '3500']], 'variables the defaults do not declare are ignored')
    assert.equal(O.layout('hyprvars', text, O.effective(defaults, h.overrides, h.removed)), '# schedule\n$night_temp = 3500\nprofile {\n    temperature = $night_temp\n}\n')
    assert.equal(O.serialize('hyprvars', h.overrides), '$night_temp = 3500\n')
}
{
    const text = '$t = 4000 # warm\n$h = a##b # c\n'
    const defaults = O.parse('hyprvars', text)
    assert.deepEqual([...defaults], [['t', '4000'], ['h', 'a##b']])
    const same = O.harvest('hyprvars', { defaults, last: defaults, live: O.parse('hyprvars', '$t = 4000\n'), overrides: new Map(), removed: new Set() })
    assert.equal(same.overrides.size, 0, 'a trailing comment is not part of the value')
    assert.equal(O.layout('hyprvars', text, defaults), text)
    assert.equal(O.layout('hyprvars', text, map({ t: '3500', h: 'x##y' })), '$t = 3500 # warm\n$h = x##y # c\n')
}
console.log('ok: hyprvars overlay')

assert.equal(O.serialize('ini', new Map()), '')
assert.equal(O.serialize('ini', map({ [ini('Settings', 'a')]: '1' })), '[Settings]\na=1\n')
console.log('ok: serialize')
