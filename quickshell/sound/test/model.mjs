import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import * as model from '../model.mjs'

const { deriveLabel, parseHidden, parseNames, classify, playing, channelTag, batteryFor, deviceList, routeTargets, appList, streamBySerial, routeReached, badge } = model
const nodes = JSON.parse(readFileSync(new URL('./fixtures/nodes.json', import.meta.url), 'utf8'))
const copy = x => JSON.parse(JSON.stringify(x))

const BUILTIN = 'alsa_output.pci-0000_00_1f.3.analog-stereo'
const G533 = 'alsa_output.usb-Logitech_G533_Gaming_Headset-00.analog-stereo'
const HDMI = 'alsa_output.pci-0000_01_00.1.hdmi-stereo'
const SURROUND = 'effect_input.virtual_surround'
const G533_MIC = 'alsa_input.usb-Logitech_G533_Gaming_Headset-00.mono-fallback'
const BUILTIN_MIC = 'alsa_input.pci-0000_00_1f.3.analog-stereo'
const byName = name => nodes.find(n => n.name === name)

// deriveLabel: the spec's four rules in order.
assert.equal(deriveLabel('[G533 Wireless Headset Dongle] Analog Stereo', false), 'G533 Wireless Headset Dongle')
assert.equal(deriveLabel('Built-in Audio Analog Stereo', false), 'Built-in Audio')
assert.equal(deriveLabel('GA102 High Definition Audio Controller Digital Stereo (HDMI) [ROG PG279Q]', false), 'ROG PG279Q')
assert.equal(deriveLabel('Virtual Surround 7.1 (headphones)', true), 'Surround 7.1')
assert.equal(deriveLabel('Analog Stereo', false), 'Analog Stereo') // empty result falls back
assert.equal(deriveLabel('[G533 Wireless Headset Dongle] Mono', false), 'G533 Wireless Headset Dongle')
assert.equal(deriveLabel('Built-in Audio Analog Surround 5.1', false), 'Built-in Audio')
assert.equal(deriveLabel('Foo Digital Stereo (IEC958)', false), 'Foo')
assert.equal(deriveLabel('Foo Digital Stereo (HDMI)', false), 'Foo')
assert.equal(deriveLabel('Virtual Surround 7.1 (headphones)', false), 'Virtual Surround 7.1 (headphones)') // rule 4 is virtual-only
assert.equal(deriveLabel(null, false), '')

// parseHidden / parseNames
assert.deepEqual(parseHidden(`${G533}\n\n  ${HDMI}  \r\n`), [G533, HDMI])
assert.deepEqual(parseHidden(''), [])
assert.deepEqual(parseNames(`${G533}\tHeadset\n${HDMI}\tMonitor\r\n`), { [G533]: 'Headset', [HDMI]: 'Monitor' })
assert.deepEqual(parseNames('a\na\t\na\tb\tc\n\t\n\tlabel\n'), {})
assert.deepEqual(parseNames('a\nok\tfine\na\t\na\tb\tc'), { ok: 'fine' })
assert.deepEqual(parseNames(''), {})
assert.deepEqual(parseNames('__proto__\tX\nok\tfine\n'), { ok: 'fine' }) // never the prototype

// classify
const c = classify(nodes)
assert.deepEqual(c.outputs.map(n => n.name).sort(), [BUILTIN, G533, HDMI].sort())
assert.deepEqual(c.virtuals.map(n => n.name), [SURROUND])
assert.ok(!c.apps.some(n => n.name === 'effect_output.virtual_surround')) // passive + virtual leg
assert.deepEqual(c.apps.map(n => n.name).sort(), ['mpv', 'pw-play'])
assert.deepEqual(c.inputs.map(n => n.name).sort(), [G533_MIC, BUILTIN_MIC].sort()) // no monitors

// Synthetic: native PipeWire has no monitor source nodes, so this one is built here.
const monitor = { id: 900, name: `${BUILTIN}.monitor`, description: 'Monitor of Built-in Audio', isSink: false, isStream: false, props: { 'media.class': 'Audio/Source/Virtual' }, volume: 1, muted: false, channels: 2, linkStates: [], linkTargets: [] }
assert.ok(!classify(nodes.concat([monitor])).inputs.some(n => n.id === 900))
// Synthetic: a passive (not virtual) stream and an input stream are not apps.
const passive = Object.assign(copy(byName('mpv')), { id: 901, name: 'passive', props: { 'media.class': 'Stream/Output/Audio', 'node.passive': true } })
const capture = Object.assign(copy(byName('mpv')), { id: 902, name: 'capture', props: { 'media.class': 'Stream/Input/Audio' } })
assert.deepEqual(classify(nodes.concat([passive, capture])).apps.map(n => n.name).sort(), ['mpv', 'pw-play'])

// playing
assert.equal(playing(byName('mpv')), true)
assert.equal(playing(Object.assign(copy(byName('mpv')), { linkStates: ['paused', 'paused'] })), false)
assert.equal(playing(Object.assign(copy(byName('mpv')), { linkStates: ['paused', 'active'] })), true)
assert.equal(playing(Object.assign(copy(byName('mpv')), { linkStates: [], linkTargets: [] })), false)
assert.equal(playing(byName('effect_output.virtual_surround')), false)

// channelTag
assert.equal(channelTag(8), '7.1')
assert.equal(channelTag(6), '5.1')
assert.equal(channelTag(2), '')
assert.equal(channelTag(1), '')

// batteryFor
const headset = { id: '1-2', name: 'G533', kind: 'headset', percent: 71, level: 'normal', charging: false, state: 'ok', usb: '046d:0a66', alert: false }
const sinks = c.outputs.concat(c.virtuals)
assert.deepEqual(batteryFor(sinks, [headset]), { [G533]: 71 })
assert.deepEqual(batteryFor(sinks, [headset, Object.assign({}, headset, { id: '1-3' })]), {})
assert.deepEqual(batteryFor(sinks, [Object.assign({}, headset, { percent: null })]), {})
assert.deepEqual(batteryFor(sinks, [Object.assign({}, headset, { usb: '046D:0A66' })]), { [G533]: 71 }) // case-insensitive
assert.deepEqual(batteryFor(sinks, [Object.assign({}, headset, { usb: '1234:abcd' })]), {})
assert.deepEqual(batteryFor(sinks, [Object.assign({}, headset, { usb: undefined })]), {})
assert.deepEqual(batteryFor(sinks, [Object.assign({}, headset, { percent: 0 })]), { [G533]: 0 })
// The source carries the same alsa.components, but only sinks are looked at.
assert.deepEqual(batteryFor(c.inputs, [headset]), {})
// Two sinks with the same components are ambiguous.
assert.deepEqual(batteryFor(sinks.concat([Object.assign(copy(byName(G533)), { id: 903, name: 'twin' })]), [headset]), {})

// deviceList
const opts = { defaultId: byName(BUILTIN).id, hidden: [], names: {}, battery: {} }
{
    const out = deviceList('output', c, opts)
    assert.deepEqual(out.shown.map(d => d.name).sort(), [BUILTIN, G533, HDMI].sort())
    assert.deepEqual(out.hidden, [])
    const builtin = out.shown.find(d => d.name === BUILTIN)
    assert.deepEqual(builtin, { key: BUILTIN, name: BUILTIN, label: 'Built-in Audio', volume: 1, muted: false, battery: null, current: true, virtual: false })
    assert.equal(out.shown.find(d => d.name === HDMI).label, 'ROG PG279Q')
    assert.equal(out.shown.filter(d => d.current).length, 1)

    // A hidden current default stays shown; another hidden device moves to hidden.
    const h = deviceList('output', c, Object.assign({}, opts, { hidden: [BUILTIN, HDMI] }))
    assert.deepEqual(h.shown.map(d => d.name).sort(), [BUILTIN, G533].sort())
    assert.deepEqual(h.hidden.map(d => d.name), [HDMI])
    assert.equal(h.shown.find(d => d.name === BUILTIN).current, true)

    // sound-names wins over deriveLabel; battery lands on its device.
    const n = deviceList('output', c, Object.assign({}, opts, { names: { [G533]: 'Headset' }, battery: { [G533]: 55 } }))
    assert.equal(n.shown.find(d => d.name === G533).label, 'Headset')
    assert.equal(n.shown.find(d => d.name === G533).battery, 55)
    assert.equal(n.shown.find(d => d.name === BUILTIN).label, 'Built-in Audio')
    // Inherited object keys are not names.
    const inh = deviceList('output', c, Object.assign({}, opts, { names: parseNames('x\ty') }))
    assert.equal(inh.shown.length, 3)

    // A virtual default is listed, marked current; otherwise virtuals are excluded.
    const v = deviceList('output', c, Object.assign({}, opts, { defaultId: byName(SURROUND).id }))
    const surround = v.shown.find(d => d.name === SURROUND)
    assert.equal(surround.current, true)
    assert.equal(surround.virtual, true)
    assert.equal(surround.label, 'Surround 7.1')
    assert.equal(v.shown.filter(d => d.current).length, 1)
    assert.ok(!out.shown.some(d => d.virtual) && !out.hidden.some(d => d.virtual))
    // A hidden virtual that is not current is excluded, not "hidden".
    const hv = deviceList('output', c, Object.assign({}, opts, { hidden: [SURROUND] }))
    assert.ok(!hv.hidden.some(d => d.name === SURROUND))

    // Inputs: current default is the G533 mic; hiding the other mic hides it.
    const inp = deviceList('input', c, { defaultId: byName(G533_MIC).id, hidden: [G533_MIC, BUILTIN_MIC], names: {}, battery: {} })
    assert.deepEqual(inp.shown.map(d => d.name), [G533_MIC])
    assert.deepEqual(inp.hidden.map(d => d.name), [BUILTIN_MIC])
    assert.equal(inp.shown[0].label, 'G533 Wireless Headset Dongle')

    // Synthetic: a virtual source (e.g. echo cancel) is a legitimate input.
    const echo = { id: 904, name: 'echo-cancel-source', description: 'Echo-Cancel Source', isSink: false, isStream: false, props: { 'media.class': 'Audio/Source', 'node.virtual': true, 'object.serial': 904 }, volume: 1, muted: false, channels: 1, linkStates: [], linkTargets: [] }
    const ec = classify(nodes.concat([echo]))
    const echoIn = deviceList('input', ec, { defaultId: byName(G533_MIC).id, hidden: [], names: {}, battery: {} })
    assert.ok(echoIn.shown.some(d => d.name === 'echo-cancel-source' && d.virtual && !d.current))
    const echoHidden = deviceList('input', ec, { defaultId: byName(G533_MIC).id, hidden: ['echo-cancel-source'], names: {}, battery: {} })
    assert.ok(echoHidden.hidden.some(d => d.name === 'echo-cancel-source'))
}

// routeTargets: shown real outputs, then virtuals; hidden outputs excluded.
{
    const t = routeTargets(c, opts)
    assert.deepEqual(t.map(x => x.name), c.outputs.map(n => n.name).concat([SURROUND]))
    assert.deepEqual(t[t.length - 1], { key: SURROUND, name: SURROUND, serial: 36, label: 'Surround 7.1', virtual: true, tag: '7.1' })
    assert.equal(t.find(x => x.name === HDMI).serial, 236)
    const th = routeTargets(c, Object.assign({}, opts, { hidden: [HDMI, G533] }))
    assert.deepEqual(th.map(x => x.name), [BUILTIN, SURROUND])
    assert.ok(!routeTargets(c, Object.assign({}, opts, { hidden: [SURROUND] })).some(x => x.name === SURROUND))
    // A hidden current default is still a target.
    const thc = routeTargets(c, Object.assign({}, opts, { hidden: [BUILTIN] }))
    assert.ok(thc.some(x => x.name === BUILTIN))
}

// appList
{
    const aopts = Object.assign({}, opts, { pins: {}, pending: {} })
    const apps = appList(c, aopts)
    assert.deepEqual(apps.map(a => a.name), ['mpv', 'pw-play'])
    const mpv = apps[0], pw = apps[1]
    assert.equal(mpv.icon, 'mpv')
    assert.equal(pw.icon, '')
    assert.equal(mpv.key, '550') // the serial: object ids are reused
    assert.equal(mpv.serial, 550)
    assert.equal(mpv.initials, 'M')
    assert.deepEqual(mpv.route, { label: 'Default', pinned: false, target: '' })
    assert.equal(mpv.pending, false)
    assert.equal(mpv.tag, '')
    assert.equal(mpv.volume, 1)
    assert.equal(mpv.muted, false)
    assert.equal(badge(apps), 2)
    assert.equal(badge([]), 0)

    // Pinned to the built-in sink while it is the default: its label, pinned.
    const pinnedDefault = appList(c, Object.assign({}, aopts, { pins: { 163: '79' } }))
    assert.deepEqual(pinnedDefault[0].route, { label: 'Built-in Audio', pinned: true, target: BUILTIN })
    // Pinned by serial (HDMI's serial is not its id), and by node name.
    assert.deepEqual(appList(c, Object.assign({}, aopts, { pins: { 163: '236' } }))[0].route, { label: 'ROG PG279Q', pinned: true, target: HDMI })
    assert.deepEqual(appList(c, Object.assign({}, aopts, { pins: { 163: G533 } }))[0].route, { label: 'G533 Wireless Headset Dongle', pinned: true, target: G533 })
    // A custom name shows on the route too.
    assert.equal(appList(c, Object.assign({}, aopts, { pins: { 163: '236' }, names: { [HDMI]: 'Monitor' } }))[0].route.label, 'Monitor')
    // Pinned to a serial no sink has: Default, not pinned.
    assert.deepEqual(appList(c, Object.assign({}, aopts, { pins: { 163: '9999' } }))[0].route, { label: 'Default', pinned: false, target: '' })
    // A pin on another stream does not touch this one.
    assert.equal(appList(c, Object.assign({}, aopts, { pins: { 107: '236' } }))[0].route.pinned, false)
    // A pin can name a virtual sink even though it is not shown as a device.
    assert.equal(appList(c, Object.assign({}, aopts, { pins: { 163: '36' } }))[0].route.label, 'Surround 7.1')
    // A hidden target still resolves for an existing pin.
    assert.equal(appList(c, Object.assign({}, aopts, { pins: { 163: '236' }, hidden: [HDMI] }))[0].route.label, 'ROG PG279Q')

    // Pending shows the requested target.
    const pend = appList(c, Object.assign({}, aopts, { pending: { 550: G533 } }))
    assert.equal(pend[0].pending, true)
    assert.equal(pend[0].route.label, 'G533 Wireless Headset Dongle')
    assert.equal(pend[1].pending, false)
    assert.equal(appList(c, Object.assign({}, aopts, { pending: { 550: 'default' } }))[0].route.label, 'Default')
    // Pinned and pending at once: pinned comes from the pin, the label from the pending target.
    const pinnedAndPending = appList(c, Object.assign({}, aopts, { pins: { 163: '236' }, pending: { 550: G533 } }))[0]
    assert.equal(pinnedAndPending.pending, true)
    assert.equal(pinnedAndPending.route.pinned, true)
    assert.equal(pinnedAndPending.route.label, 'G533 Wireless Headset Dongle')
    assert.equal(pinnedAndPending.route.target, G533)
    // A pin that resolves to no sink stays unpinned even with a pending entry.
    assert.equal(appList(c, Object.assign({}, aopts, { pins: { 163: '9999' }, pending: { 550: G533 } }))[0].route.pinned, false)

    // Tag: a stream linked into the surround sink reads 7.1.
    const mpvIn = Object.assign(copy(byName('mpv')), { linkTargets: [36, 36] })
    const tagged = appList(classify(nodes.map(n => n.name === 'mpv' ? mpvIn : n)), aopts)
    assert.equal(tagged[0].tag, '7.1')
    assert.equal(tagged[1].tag, '')

    // Paused apps are not listed; a null description does not throw; initials take two words.
    const paused = Object.assign(copy(byName('mpv')), { linkStates: ['paused', 'paused'] })
    assert.deepEqual(appList(classify(nodes.map(n => n.name === 'mpv' ? paused : n)), aopts).map(a => a.name), ['pw-play'])
    // A stream relinking after a route has no active link for a moment: its
    // pending entry keeps it listed, so the row does not blink out.
    const relinking = classify(nodes.map(n => n.name === 'mpv' ? paused : n))
    const kept = appList(relinking, Object.assign({}, aopts, { pending: { 550: G533 } })).find(a => a.key === '550')
    assert.ok(kept, 'a pending stream with no active link is listed')
    assert.equal(kept.pending, true)
    assert.equal(appList(relinking, aopts).find(a => a.key === '550'), undefined)
    const two = { id: 500, name: 'x', description: 'google chrome browser', isSink: false, isStream: true, props: { 'media.class': 'Stream/Output/Audio', 'object.serial': 501, 'application.icon_name': 'chrome' }, volume: 0.5, muted: true, channels: 2, linkStates: ['active'], linkTargets: [79] }
    const chrome = appList(classify(nodes.concat([two])), aopts).find(a => a.key === '501')
    assert.equal(chrome.initials, 'GC')
    assert.equal(chrome.icon, 'chrome')
    assert.equal(chrome.name, 'google chrome browser')
    assert.equal(chrome.muted, true)
    // The hyphenated key wins over the underscore one.
    const both = Object.assign(copy(two), { id: 501, props: Object.assign(copy(two.props), { 'application.icon-name': 'real' }) })
    assert.equal(appList(classify(nodes.concat([both])), aopts).find(a => a.key === '501').icon, 'real')

    // mpv ends and a new stream takes its object id 163 with serial 600: a
    // different row, and the old pending route (keyed by serial 550) is not its.
    const reused = Object.assign(copy(byName('mpv')), { name: 'next', props: Object.assign(copy(byName('mpv').props), { 'object.serial': 600 }), linkStates: ['paused', 'paused'] })
    const afterEnd = classify(nodes.map(n => n.name === 'mpv' ? reused : n))
    assert.equal(appList(afterEnd, Object.assign({}, aopts, { pending: { 550: G533 } })).find(a => a.key === '600'), undefined, 'the replacement does not inherit the pending route')
    const playingReused = Object.assign(copy(reused), { linkStates: ['active', 'active'] })
    const next = appList(classify(nodes.map(n => n.name === 'mpv' ? playingReused : n)), Object.assign({}, aopts, { pending: { 550: G533 } })).find(a => a.key === '600')
    assert.ok(next, 'the replacement is its own row')
    assert.notEqual(next.key, mpv.key)
    assert.equal(next.pending, false)
    assert.equal(next.route.label, 'Default')
    // Pins stay keyed by object id: a pin on id 163 now belongs to the new stream.
    assert.equal(appList(classify(nodes.map(n => n.name === 'mpv' ? playingReused : n)), Object.assign({}, aopts, { pins: { 163: '236' } })).find(a => a.key === '600').route.target, HDMI)
}

// streamBySerial / routeReached: a pending route settles only on its own stream.
{
    assert.equal(streamBySerial(nodes, 550).name, 'mpv')
    assert.equal(streamBySerial(nodes, '550').name, 'mpv')
    assert.equal(streamBySerial(nodes, 79), null) // a sink's serial is not a stream
    assert.equal(streamBySerial(nodes, 9999), null)
    const builtinId = byName(BUILTIN).id
    // mpv is linked into the built-in sink.
    assert.equal(routeReached(nodes, '550', BUILTIN, builtinId), true)
    assert.equal(routeReached(nodes, '550', 'default', builtinId), true)
    assert.equal(routeReached(nodes, '550', G533, builtinId), false)
    assert.equal(routeReached(nodes, '550', 'default', byName(G533).id), false)
    assert.equal(routeReached(nodes, '550', 'alsa_output.gone', builtinId), false)
    // A request whose stream ended is never reached, even when a stream that
    // took its object id is linked into the target.
    const reused = Object.assign(copy(byName('mpv')), { props: Object.assign(copy(byName('mpv').props), { 'object.serial': 600 }), linkTargets: [77, 77] })
    const after = nodes.map(n => n.name === 'mpv' ? reused : n)
    assert.equal(routeReached(after, '550', G533, builtinId), false)
    assert.equal(routeReached(after, '600', G533, builtinId), true)
}

console.log('sound model ok')
