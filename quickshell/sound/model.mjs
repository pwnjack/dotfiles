// Pure model for the sound popover (QML imports it) and the Settings panel's
// device names (which re-exports deriveLabel, parseHidden and parseNames), so
// both surfaces label a device the same way. No I/O: callers pass everything in.
//
// Kept inside what Qt's V4 engine runs: no object spread, matchAll, trimEnd,
// Object.hasOwn, Array.at or TextEncoder.
//
// A NodeIn is what the adapter builds from a PwNode: { id, name, description,
// isSink, isStream, props, volume, muted, channels, linkStates, linkTargets }.
// linkStates are lowercase PwLinkState names and linkTargets the object ids of
// the nodes a stream is linked into; links are per channel, so a stereo stream
// has two of each.

const PROFILE_PHRASES = [
    /Analog Surround \d\.\d/g,
    /Analog Stereo/g,
    /Digital Stereo \(HDMI\)/g,
    /Digital Stereo \(IEC958\)/g,
    /\bMono\b/g,
]
// An HDMI or DisplayPort profile followed by the monitor's name in brackets.
const MONITOR_NAME = /(?:HDMI|DisplayPort)[^\[\]]*\s\[([^\]]+)\]\s*$/

function tidy(text) {
    return text.replace(/\s+/g, ' ').replace(/^ | $/g, '')
}

function own(object, key) {
    return !!object && Object.prototype.hasOwnProperty.call(object, key)
}

export function deriveLabel(description, virtual) {
    const original = description || ''
    const monitor = MONITOR_NAME.exec(original)
    if (monitor && tidy(monitor[1])) return tidy(monitor[1])
    let text = original
    for (let i = 0; i < PROFILE_PHRASES.length; i++) text = text.replace(PROFILE_PHRASES[i], ' ')
    text = tidy(text.replace(/\[([^\]]*)\]/g, '$1'))
    if (virtual) text = tidy(text.replace(/\s*\([^)]*\)\s*$/, '').replace(/^Virtual\s+/, ''))
    return text || original
}

export function parseHidden(text) {
    const names = []
    const lines = String(text || '').split('\n')
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim()
        if (line) names.push(line)
    }
    return names
}

// node.name <TAB> label, one per line. A line without exactly one tab, or with
// an empty name or label, is skipped.
export function parseNames(text) {
    const names = {}
    const lines = String(text || '').split('\n')
    for (let i = 0; i < lines.length; i++) {
        const parts = lines[i].replace(/\r$/, '').split('\t')
        if (parts.length !== 2) continue
        const name = parts[0].trim()
        const label = parts[1].trim()
        if (name && label && name !== '__proto__') names[name] = label
    }
    return names
}

export function classify(nodes) {
    const out = { outputs: [], virtuals: [], inputs: [], apps: [] }
    for (let i = 0; i < nodes.length; i++) {
        const node = nodes[i]
        const props = node.props || {}
        const mediaClass = props['media.class']
        if (node.isSink) {
            if (props['node.virtual'] === true) out.virtuals.push(node)
            else out.outputs.push(node)
        } else if (node.isStream) {
            if (mediaClass === 'Stream/Output/Audio' && props['node.virtual'] !== true && props['node.passive'] !== true) out.apps.push(node)
        } else if (mediaClass === 'Audio/Source') {
            out.inputs.push(node)
        }
    }
    return out
}

export function playing(node) {
    const states = node.linkStates || []
    for (let i = 0; i < states.length; i++) if (states[i] === 'active') return true
    return false
}

export function channelTag(channels) {
    return channels === 8 ? '7.1' : channels === 6 ? '5.1' : ''
}

// node.name -> percent. Sinks only: a headset's source carries the same
// alsa.components. No entry when the match is not unique on either side.
export function batteryFor(sinks, headsets) {
    const result = {}
    const count = {}
    for (let i = 0; i < headsets.length; i++) {
        const usb = headsets[i].usb ? String(headsets[i].usb).toLowerCase() : ''
        if (usb) count[usb] = (count[usb] || 0) + 1
    }
    for (let i = 0; i < headsets.length; i++) {
        const row = headsets[i]
        const usb = row.usb ? String(row.usb).toLowerCase() : ''
        if (!usb || count[usb] !== 1 || typeof row.percent !== 'number') continue
        const wanted = 'usb' + usb
        let match = null
        let matches = 0
        for (let j = 0; j < sinks.length; j++) {
            if (!sinks[j].isSink) continue
            const components = String((sinks[j].props || {})['alsa.components'] || '').toLowerCase()
            if (components.indexOf(wanted) >= 0) {
                match = sinks[j]
                matches++
            }
        }
        if (matches === 1) result[match.name] = row.percent
    }
    return result
}

function labelFor(node, names) {
    if (own(names, node.name)) return names[node.name]
    return deriveLabel(node.description, node.props['node.virtual'] === true)
}

function deviceView(node, opts) {
    const battery = opts.battery
    return {
        key: node.name,
        name: node.name,
        label: labelFor(node, opts.names),
        volume: node.volume,
        muted: node.muted,
        battery: own(battery, node.name) && typeof battery[node.name] === 'number' ? battery[node.name] : null,
        current: node.id === opts.defaultId,
        virtual: node.props['node.virtual'] === true,
    }
}

// The current default is always shown, even hidden or virtual. Other virtual
// sinks are never picker entries (virtual sources, e.g. echo cancel, are inputs);
// other hidden devices go to `hidden`.
export function deviceList(kind, c, opts) {
    const hidden = opts.hidden || []
    const candidates = kind === 'output' ? c.outputs.concat(c.virtuals) : c.inputs
    const view = { names: opts.names || {}, battery: opts.battery || {}, defaultId: opts.defaultId }
    const result = { shown: [], hidden: [] }
    for (let i = 0; i < candidates.length; i++) {
        const node = candidates[i]
        const device = deviceView(node, view)
        if (device.current) result.shown.push(device)
        else if (kind === 'output' && device.virtual) continue
        else if (hidden.indexOf(node.name) >= 0) result.hidden.push(device)
        else result.shown.push(device)
    }
    return result
}

// Shown real outputs, then virtual sinks. Unlike the picker, a virtual sink is
// a target whether or not it is the default; hiding still removes it.
export function routeTargets(c, opts) {
    const names = opts.names || {}
    const hidden = opts.hidden || []
    const targets = []
    const lists = [c.outputs, c.virtuals]
    for (let k = 0; k < lists.length; k++) {
        for (let i = 0; i < lists[k].length; i++) {
            const node = lists[k][i]
            if (node.id !== opts.defaultId && hidden.indexOf(node.name) >= 0) continue
            targets.push({
                key: node.name,
                name: node.name,
                serial: node.props['object.serial'],
                label: labelFor(node, names),
                virtual: k === 1,
                tag: channelTag(node.channels),
            })
        }
    }
    return targets
}

function findSink(c, ref) {
    const sinks = c.outputs.concat(c.virtuals)
    for (let i = 0; i < sinks.length; i++) {
        if (String(sinks[i].props['object.serial']) === String(ref) || sinks[i].name === ref) return sinks[i]
    }
    return null
}

function initialsOf(name) {
    const words = name.split(/\s+/)
    let text = ''
    for (let i = 0; i < words.length && i < 2; i++) if (words[i]) text += words[i].charAt(0)
    return text.toUpperCase()
}

function byAppName(a, b) {
    const x = a.name.toLowerCase()
    const y = b.name.toLowerCase()
    return x < y ? -1 : x > y ? 1 : a.key < b.key ? -1 : a.key > b.key ? 1 : 0
}

// A stream is keyed by its object.serial: PipeWire reuses object ids, so a
// new stream can take an ended one's id. `pins` stays keyed by object id, as
// pw-metadata writes it.
//
// A route only reads as pinned when `pins` names the stream: PipeWire records
// a stream routed to the current default as unpinned. `pending` (key -> target
// node name, or "default") shows a requested route until the stream follows,
// and keeps the stream listed while it relinks with no active link.
export function appList(c, opts) {
    const names = opts.names || {}
    const pins = opts.pins || {}
    const pending = opts.pending || {}
    const apps = []
    for (let i = 0; i < c.apps.length; i++) {
        const node = c.apps[i]
        const props = node.props
        const key = String(props['object.serial'])
        const isPending = own(pending, key)
        if (!playing(node) && !isPending) continue
        const name = props['application.name'] || node.description || node.name
        const id = String(node.id)
        const pin = own(pins, id) ? findSink(c, pins[id]) : null
        const sink = isPending ? findSink(c, pending[key]) : pin
        let tag = ''
        for (let j = 0; j < c.virtuals.length && !tag; j++) {
            if (node.linkTargets.indexOf(c.virtuals[j].id) >= 0) tag = channelTag(c.virtuals[j].channels)
        }
        apps.push({
            key,
            serial: props['object.serial'],
            name,
            icon: props['application.icon-name'] || props['application.icon_name'] || '',
            initials: initialsOf(name),
            volume: node.volume,
            muted: node.muted,
            route: {
                label: sink ? labelFor(sink, names) : 'Default',
                pinned: !!pin,
                target: sink ? sink.name : '',
            },
            tag,
            pending: isPending,
        })
    }
    return apps.sort(byAppName)
}

// The output stream whose object.serial is `serial`, or null once it ended.
export function streamBySerial(nodes, serial) {
    for (let i = 0; i < nodes.length; i++) {
        if (nodes[i].isStream && String((nodes[i].props || {})['object.serial']) === String(serial)) return nodes[i]
    }
    return null
}

// Has the stream with this serial linked into `target` (a sink's node.name, or
// "default" for the actual default output, object id `defaultId`)? A stream
// that ended is never there, even when a new one took its object id.
export function routeReached(nodes, serial, target, defaultId) {
    const stream = streamBySerial(nodes, serial)
    if (!stream) return false
    let sinkId = target === 'default' ? defaultId : -1
    for (let i = 0; i < nodes.length && sinkId < 0; i++) {
        if (nodes[i].isSink && nodes[i].name === target) sinkId = nodes[i].id
    }
    return sinkId >= 0 && stream.linkTargets.indexOf(sinkId) >= 0
}

export function badge(apps) {
    return apps.length
}
