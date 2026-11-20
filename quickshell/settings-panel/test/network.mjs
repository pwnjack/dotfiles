import assert from 'node:assert/strict'
import * as network from '../network.mjs'

// Flag values from libnm: PRIVACY=0x1; PSK=0x100, 802.1X=0x200, SAE=0x400, OWE=0x800.
// 392 (0x188) is what this machine's WPA2 access points report.
const snap = {
    running: true, wifiEnabled: true, wifiDevices: [{iface: 'wlan0'}],
    accessPoints: [
        {ssid: 'Home', strength: 40, flags: 1, wpaFlags: 0, rsnFlags: 392},
        {ssid: 'Home', strength: 84, flags: 1, wpaFlags: 0, rsnFlags: 392},
        {ssid: 'Cafe', strength: 90, flags: 0, wpaFlags: 0, rsnFlags: 0},
        {ssid: 'Office', strength: 70, flags: 1, wpaFlags: 0, rsnFlags: 0x200},
        {ssid: 'New3', strength: 60, flags: 1, wpaFlags: 0, rsnFlags: 0x400},
        {ssid: 'Old', strength: 20, flags: 1, wpaFlags: 0, rsnFlags: 0},
        {ssid: '', strength: 99, flags: 1, wpaFlags: 0, rsnFlags: 392},
        {ssid: 'Saved', strength: 10, flags: 1, wpaFlags: 0, rsnFlags: 392},
    ],
    wired: [{iface: 'eno1', carrier: true, speed: 1000, ip4: '192.168.1.10/24', gateway: '192.168.1.1'}],
    connections: [
        {uuid: 'u-saved', id: 'Saved', type: '802-11-wireless', ssid: 'Saved', state: null, iface: null},
        {uuid: 'u-saved2', id: 'Saved 1', type: '802-11-wireless', ssid: 'Saved', state: null, iface: null},
        {uuid: 'u-home', id: 'Home', type: '802-11-wireless', ssid: 'Home', state: 'activated', iface: 'wlan0'},
        {uuid: 'u-proton', id: 'ProtonVPN IT#113', type: 'wireguard', ssid: null, state: 'activated', iface: 'proton0'},
        {uuid: 'u-work', id: 'Work', type: 'vpn', ssid: null, state: null, iface: null},
        {uuid: 'u-kill', id: 'pvpn-killswitch-ipv6', type: 'dummy', ssid: null, state: 'activated', iface: 'ipv6leakintrf0'},
        {uuid: 'u-wired', id: 'Wired connection 1', type: '802-3-ethernet', ssid: null, state: 'activated', iface: 'eno1'},
    ],
}

const list = network.wifiNetworks(snap)
assert.deepEqual(list.map(n => n.ssid), ['Home', 'Saved', 'Cafe', 'Office', 'New3', 'Old'])
assert.equal(list[0].signal, 84)
assert.equal(list[0].active, true)
assert.equal(list[1].known, true)
assert.deepEqual(list.map(n => n.bars), [4, 1, 4, 3, 3, 1])
console.log('ok: networks grouped by SSID, hidden dropped, active/known/signal order')

assert.deepEqual(['Cafe', 'Home', 'Office', 'New3', 'Old'].map(ssid => list.find(n => n.ssid === ssid).security), ['open', 'psk', 'unsupported', 'sae', 'unsupported'])
for (const [ap, expected] of [
    [{flags: 1, wpaFlags: 0, rsnFlags: 0x500}, 'psk'],
    [{flags: 1, wpaFlags: 0, rsnFlags: 0x300}, 'psk'],
    [{flags: 1, wpaFlags: 0, rsnFlags: 0x600}, 'sae'],
    [{flags: 1, wpaFlags: 0x100, rsnFlags: 0}, 'psk'],
    [{flags: 1, wpaFlags: 0, rsnFlags: 0x800}, 'owe'],
    [{flags: 1, wpaFlags: 0, rsnFlags: 0x1000}, 'owe'],
    [{flags: 1, wpaFlags: 0, rsnFlags: 0x1800}, 'owe'],
    [{flags: 1, wpaFlags: 0, rsnFlags: 0}, 'unsupported'],
    [{flags: 0, wpaFlags: 0, rsnFlags: 0}, 'open'],
]) assert.equal(network.securityOf(ap), expected)
console.log('ok: security precedence covers PSK, SAE, 802.1X, WPA1, OWE, WEP, and open')

// Fail-closed, strongest-wins: a weaker BSS sharing the SSID must never
// downgrade the connection away from the strongest security any BSS
// advertises — PSK next to SAE is the WPA3 transition downgrade, open next to
// OWE/802.1X/WEP is an unauthenticated downgrade. Signal/bars come from the
// strongest BSS that is actually compatible with the chosen security, which
// can be a weaker BSS than the strongest sighting overall.
for (const [label, aps, expectedSecurity, expectedSignal] of [
    ['PSK+SAE-only', [
        {strength: 90, flags: 1, wpaFlags: 0, rsnFlags: 0x400}, // SAE-only, strongest and compatible
        {strength: 20, flags: 1, wpaFlags: 0, rsnFlags: 0x100}, // PSK-only
    ], 'sae', 90],
    ['PSK + transition', [
        {strength: 90, flags: 1, wpaFlags: 0, rsnFlags: 0x100}, // PSK-only, strongest but not SAE-compatible
        {strength: 20, flags: 1, wpaFlags: 0, rsnFlags: 0x500}, // PSK+SAE transition, weaker but compatible
    ], 'sae', 20],
    ['open + OWE', [
        {strength: 90, flags: 0, wpaFlags: 0, rsnFlags: 0}, // open, strongest but not OWE-compatible
        {strength: 10, flags: 1, wpaFlags: 0, rsnFlags: 0x800}, // OWE, weaker but compatible
    ], 'owe', 10],
    ['open + OWE transition-mode', [
        {strength: 90, flags: 0, wpaFlags: 0, rsnFlags: 0},
        {strength: 10, flags: 1, wpaFlags: 0, rsnFlags: 0x1000},
    ], 'owe', 10],
    ['open + 802.1X', [
        {strength: 90, flags: 0, wpaFlags: 0, rsnFlags: 0},
        {strength: 5, flags: 1, wpaFlags: 0, rsnFlags: 0x200},
    ], 'unsupported', 5],
    ['open + WEP', [
        {strength: 90, flags: 0, wpaFlags: 0, rsnFlags: 0},
        {strength: 5, flags: 1, wpaFlags: 0, rsnFlags: 0},
    ], 'unsupported', 5],
]) {
    const net = network.wifiNetworks({...snap, connections: [], accessPoints: aps.map(ap => ({ssid: label, ...ap}))})[0]
    assert.equal(net.security, expectedSecurity, `${label}: security must fail closed to the strongest`)
    assert.equal(net.signal, expectedSignal, `${label}: signal must come from the compatible BSS`)
}
console.log('ok: mixed-BSS security fails closed to the strongest security across an SSID, signal from the compatible BSS')

for (const [ap, security, expected] of [
    [{flags: 1, wpaFlags: 0, rsnFlags: 0x400}, 'sae', true],
    [{flags: 1, wpaFlags: 0, rsnFlags: 0x500}, 'sae', true], // transition satisfies sae too
    [{flags: 1, wpaFlags: 0, rsnFlags: 0x100}, 'sae', false],
    [{flags: 1, wpaFlags: 0, rsnFlags: 0x100}, 'psk', true],
    [{flags: 1, wpaFlags: 0, rsnFlags: 0x400}, 'psk', false],
    [{flags: 1, wpaFlags: 0, rsnFlags: 0x800}, 'owe', true],
    [{flags: 1, wpaFlags: 0, rsnFlags: 0x1000}, 'owe', true],
    [{flags: 1, wpaFlags: 0, rsnFlags: 0x100}, 'owe', false],
    [{flags: 0, wpaFlags: 0, rsnFlags: 0}, 'open', true],
    [{flags: 1, wpaFlags: 0, rsnFlags: 0}, 'open', false],
    [{flags: 1, wpaFlags: 0, rsnFlags: 0x200}, 'unsupported', true],
    [{flags: 1, wpaFlags: 0, rsnFlags: 0}, 'unsupported', true],
    [{flags: 1, wpaFlags: 0, rsnFlags: 0x100}, 'unsupported', false],
]) assert.equal(network.apSupports(ap, security), expected)
console.log('ok: apSupports matches a BSS against a group security, transition BSSs included for sae')

const edgeBars = network.wifiNetworks({...snap, connections: [], accessPoints: [
    {ssid: 'Zero', strength: 0, flags: 0, wpaFlags: 0, rsnFlags: 0},
    {ssid: 'Full', strength: 100, flags: 0, wpaFlags: 0, rsnFlags: 0},
]})
assert.deepEqual(Object.fromEntries(edgeBars.map(n => [n.ssid, n.bars])), {Full: 4, Zero: 1})
const nameOrder = network.wifiNetworks({...snap, connections: [], accessPoints: [
    {ssid: 'Zulu', strength: 50, flags: 0, wpaFlags: 0, rsnFlags: 0},
    {ssid: 'Alpha', strength: 50, flags: 0, wpaFlags: 0, rsnFlags: 0},
]})
assert.deepEqual(nameOrder.map(n => n.ssid), ['Alpha', 'Zulu'])
const progressOrder = network.wifiNetworks({...snap, accessPoints: [
    {ssid: 'Unknown', strength: 100, flags: 0, wpaFlags: 0, rsnFlags: 0},
    {ssid: 'Known', strength: 90, flags: 0, wpaFlags: 0, rsnFlags: 0},
    {ssid: 'Starting', strength: 20, flags: 0, wpaFlags: 0, rsnFlags: 0},
    {ssid: 'Active', strength: 10, flags: 0, wpaFlags: 0, rsnFlags: 0},
], connections: [
    {uuid: 'u-known', id: 'Known', type: '802-11-wireless', ssid: 'Known', state: null},
    {uuid: 'u-starting', id: 'Starting', type: '802-11-wireless', ssid: 'Starting', state: 'activating'},
    {uuid: 'u-active', id: 'Active', type: '802-11-wireless', ssid: 'Active', state: 'activated'},
]})
assert.deepEqual(progressOrder.map(n => n.ssid), ['Active', 'Starting', 'Known', 'Unknown'])
assert.equal(progressOrder[0].activating, false)
assert.equal(progressOrder[1].activating, true)
console.log('ok: signal bars, name tiebreak, and connection progress order')

assert.deepEqual(network.vpnConnections(snap).map(v => [v.name, v.state, v.control]),
    [['ProtonVPN IT#113', 'activated', 'app'], ['Work', 'off', 'switch']])
const vpnOrder = network.vpnConnections({...snap, connections: [
    {uuid: 'u-off', id: 'Alpha', type: 'vpn', state: null},
    {uuid: 'u-starting', id: 'Zulu', type: 'vpn', state: 'activating'},
    {uuid: 'u-active', id: 'Middle', type: 'vpn', state: 'activated'},
]})
assert.deepEqual(vpnOrder.map(v => v.name), ['Middle', 'Zulu', 'Alpha'])
console.log('ok: VPN list has vpn/wireguard only, Proton controlled by its app')

const view = network.networkView(snap, {protonApp: true})
assert.equal(view.running, true)
assert.equal(view.wifi.available, true)
assert.deepEqual(view.proton, {mode: 'app', active: true})
assert.equal(view.wired[0].iface, 'eno1')
assert.deepEqual(network.networkView({running: false}), {running: false})
assert.equal(network.networkView({...snap, wifiDevices: []}).wifi.available, false)
assert.equal(network.networkView(snap, {protonApp: false}).proton, null)
console.log('ok: page model, including NM down and no Wi-Fi device')

assert.deepEqual(network.connectPlan(snap, {ssid: 'Saved'}), {kind: 'activate', uuid: 'u-saved'})
assert.deepEqual(network.connectPlan(snap, {ssid: 'Saved', psk: ''}), {kind: 'activate', uuid: 'u-saved'})
assert.deepEqual(network.connectPlan(snap, {ssid: 'Cafe'}), {kind: 'add', ssid: 'Cafe', psk: null, keyMgmt: null, replace: []})
assert.deepEqual(network.connectPlan(snap, {ssid: 'New3', psk: 'correct horse'}), {kind: 'add', ssid: 'New3', psk: 'correct horse', keyMgmt: 'sae', replace: []})
assert.deepEqual(network.connectPlan(snap, {ssid: 'New3', psk: 'pässwörd1'}), {kind: 'add', ssid: 'New3', psk: 'pässwörd1', keyMgmt: 'sae', replace: []})
assert.deepEqual(network.connectPlan(snap, {ssid: 'New3', psk: 'x'.repeat(70)}), {kind: 'add', ssid: 'New3', psk: 'x'.repeat(70), keyMgmt: 'sae', replace: []})
assert.deepEqual(network.connectPlan(snap, {ssid: 'Saved', psk: 'f'.repeat(64)}), {kind: 'add', ssid: 'Saved', psk: 'f'.repeat(64), keyMgmt: 'wpa-psk', replace: ['u-saved', 'u-saved2']})
const oweSnap = {...snap, connections: [], accessPoints: [{ssid: 'Cafe OWE', strength: 55, flags: 1, wpaFlags: 0, rsnFlags: 0x800}]}
assert.deepEqual(network.connectPlan(oweSnap, {ssid: 'Cafe OWE'}), {kind: 'add', ssid: 'Cafe OWE', psk: null, keyMgmt: 'owe', replace: []})
// A password supplied for an open/OWE network must be refused, not silently
// dropped into an unauthenticated connection that then deletes the old saved profiles.
assert.throws(() => network.connectPlan(snap, {ssid: 'Cafe', psk: 'somepassword'}), /does not use a password/)
assert.throws(() => network.connectPlan(oweSnap, {ssid: 'Cafe OWE', psk: 'somepassword'}), /does not use a password/)
const savedOpenSnap = {...snap,
    accessPoints: [{ssid: 'SavedOpen', strength: 15, flags: 0, wpaFlags: 0, rsnFlags: 0}],
    connections: [{uuid: 'u-saved-open', id: 'SavedOpen', type: '802-11-wireless', ssid: 'SavedOpen', state: null}],
}
assert.deepEqual(network.connectPlan(savedOpenSnap, {ssid: 'SavedOpen'}), {kind: 'activate', uuid: 'u-saved-open'})
// A lone PSK+SAE transition BSS still advertises SAE, so the group (and the
// connect plan) prefers the stronger method even with no competing BSS.
const transitionSnap = {...snap, connections: [], accessPoints: [{ssid: 'Transition', strength: 55, flags: 1, wpaFlags: 0, rsnFlags: 0x500}]}
assert.deepEqual(network.connectPlan(transitionSnap, {ssid: 'Transition', psk: 'transition pass'}),
    {kind: 'add', ssid: 'Transition', psk: 'transition pass', keyMgmt: 'sae', replace: []})
const utf8Ssid = 'é'.repeat(16)
assert.deepEqual(network.connectPlan({...snap, connections: [], accessPoints: [{ssid: utf8Ssid, strength: 50, flags: 0, wpaFlags: 0, rsnFlags: 0}]}, {ssid: utf8Ssid}),
    {kind: 'add', ssid: utf8Ssid, psk: null, keyMgmt: null, replace: []})
// A non-UTF-8 SSID's display form (libnm's escaped rendering) maps each raw
// byte to one code point: a valid 17-byte Latin-1 SSID can render as 17 'é'
// characters, which is well under the 32-byte limit and must be accepted even
// though 17 'é' would be 34 bytes if re-encoded as UTF-8.
const latin1Ssid = 'é'.repeat(17)
assert.deepEqual(network.connectPlan({...snap, connections: [], accessPoints: [{ssid: latin1Ssid, strength: 50, flags: 0, wpaFlags: 0, rsnFlags: 0}]}, {ssid: latin1Ssid}),
    {kind: 'add', ssid: latin1Ssid, psk: null, keyMgmt: null, replace: []})
for (const [request, message] of [
    [{ssid: 'Old'}, /not supported/],
    [{ssid: 'Office'}, /not supported/],
    [{ssid: 'Gone'}, /no longer in range/],
    [{ssid: 'Home', psk: 'short'}, /8–63/],
    [{ssid: 'Home', psk: 'x'.repeat(64)}, /8–63/],
    [{ssid: 'Home', psk: 'ok but\nnewline'}, /8–63/],
    [{ssid: 'New3'}, /Enter the network password/],
    [{ssid: 'New3', psk: ''}, /Enter the network password/],
    [{ssid: 'New3', psk: 'bad\npassword'}, /must not be empty or contain line breaks/],
    [{ssid: 'New3', psk: 'x'.repeat(257)}, /too long/],
    [{ssid: ''}, /Invalid network name/],
    [{ssid: 'x'.repeat(33)}, /Invalid network name/],
    [{ssid: 'é'.repeat(33)}, /Invalid network name/],
    [{ssid: 42}, /Invalid network name/],
]) assert.throws(() => network.connectPlan(snap, request), message)
assert.throws(() => network.connectPlan({...snap, connections: [...snap.connections, {uuid: 'u-gone', id: 'Gone', type: '802-11-wireless', ssid: 'Gone', state: null}]}, {ssid: 'Gone'}), /no longer in range/)
// The Connect button's check: "" for an acceptable password at either limit.
assert.equal(network.passwordProblem('psk', 'x'.repeat(63)), '')
assert.equal(network.passwordProblem('sae', 'é'.repeat(128)), '')
assert.match(network.passwordProblem('sae', 'é'.repeat(129)), /too long/)
console.log('ok: connect plans and every refusal')

assert.deepEqual(network.forgetPlan(snap, 'Saved'), ['u-saved', 'u-saved2'])
assert.throws(() => network.forgetPlan(snap, 'Cafe'), /not saved/)
assert.throws(() => network.forgetPlan(snap, '\n'), /Invalid network name/)
console.log('ok: forget removes every saved profile for the SSID')

assert.deepEqual(network.vpnPlan(snap, {uuid: 'u-work', active: true}), {uuid: 'u-work', active: true})
assert.throws(() => network.vpnPlan(snap, {uuid: 'u-proton', active: false}), /Proton VPN app/)
assert.throws(() => network.vpnPlan(snap, {uuid: 'u-wired', active: false}), /not a VPN/)
assert.throws(() => network.vpnPlan(snap, {uuid: 'nope', active: true}), /no longer exists/)
assert.throws(() => network.vpnPlan(snap, {active: true}), /no longer exists/)
assert.throws(() => network.vpnPlan(snap, {uuid: 'u-work', active: 'yes'}), /on\/off/)
assert.equal(network.failureMessage('NO_SECRETS'), 'Wrong password')
assert.equal(network.failureMessage('LOGIN_FAILED'), 'Wrong password')
assert.equal(network.failureMessage('CONNECT_TIMEOUT'), 'The network did not answer in time')
assert.equal(network.failureMessage('SOMETHING_NEW'), 'Connection failed (something new)')
assert.equal(network.failureMessage('constructor'), 'Connection failed (constructor)')
assert.equal(network.failureMessage(undefined), 'Connection failed')
console.log('ok: VPN plans and readable failure reasons')

{
    const saved = {...snap, connections: [...snap.connections,
        {uuid: 'u-office', id: 'Office', type: '802-11-wireless', ssid: 'Office', state: null, iface: null},
        {uuid: 'u-saved-live', id: 'Saved 2', type: '802-11-wireless', ssid: 'Saved', state: 'activating', iface: 'wlan0'}]}
    assert.deepEqual(network.connectPlan(saved, {ssid: 'Office'}), {kind: 'activate', uuid: 'u-office'})
    assert.throws(() => network.connectPlan(saved, {ssid: 'Office', psk: 'password1'}), /not supported/)
    assert.deepEqual(network.connectPlan(saved, {ssid: 'Saved'}), {kind: 'activate', uuid: 'u-saved-live'})
    assert.throws(() => network.connectPlan(snap, {ssid: 'New3', psk: 'é'.repeat(129)}), /too long/)
    assert.equal(network.failureMessage(null), 'Connection failed')
}
console.log('ok: saved enterprise profiles activate, the live duplicate wins, SAE length message, null reason')

// QML's V4 engine has neither TextEncoder nor Object.hasOwn: the module must not need them.
{
    const {TextEncoder: encoder} = globalThis, hasOwn = Object.hasOwn
    delete globalThis.TextEncoder; delete Object.hasOwn
    try {
        assert.throws(() => network.connectPlan(snap, {ssid: 'é'.repeat(33)}), /Invalid network name/)
        assert.equal(network.connectPlan(snap, {ssid: 'New3', psk: 'pässwörd1'}).keyMgmt, 'sae')
        assert.deepEqual(network.forgetPlan(snap, 'Saved'), ['u-saved', 'u-saved2'])
        assert.equal(network.failureMessage('constructor'), 'Connection failed (constructor)')
    } finally { globalThis.TextEncoder = encoder; Object.hasOwn = hasOwn }
}
console.log('ok: works without TextEncoder and Object.hasOwn (QML V4)')
