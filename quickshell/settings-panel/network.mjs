// Pure Network page logic: plain objects in, plain objects out. nm.js is the
// only file that touches libnm; everything decidable lives here and is tested
// under Node.

// Decided by the Proton VPN probe in docs/settings-panel.md: "nm" lets the
// panel switch Proton's WireGuard profile like any VPN, "app" hands it to the
// Proton app because switching behind its back desyncs it.
export const PROTON_MODE = "app"

const WIFI = "802-11-wireless"
const VPN_TYPES = new Set(["vpn", "wireguard"])
// libnm NM80211ApFlags / NM80211ApSecurityFlags.
const PRIVACY = 0x1, PSK = 0x100, EAP = 0x200, SAE = 0x400, OWE = 0x800, OWE_TM = 0x1000

export function securityOf(ap) {
    const all = ap.wpaFlags | ap.rsnFlags
    if (all & PSK) return "psk"
    if (all & SAE) return "sae"
    if (all & EAP) return "unsupported"
    if (all & (OWE | OWE_TM)) return "owe"
    // PRIVACY without WPA/RSN is WEP, which the page does not offer.
    return ap.flags & PRIVACY ? "unsupported" : "open"
}
const savedWifi = snap => snap.connections.filter(c => c.type === WIFI && c.ssid)

// Fail-closed, strongest-wins: a single weaker BSS sharing the SSID must never
// downgrade the connection. unsupported (802.1X/WEP) always wins because it is
// not encrypted here; otherwise any BSS advertising SAE (a PSK+SAE transition
// BSS included) beats plain PSK, which beats OWE, which beats open.
export function groupSecurity(bsses) {
    if (bsses.some(ap => securityOf(ap) === "unsupported")) return "unsupported"
    if (bsses.some(ap => (ap.wpaFlags | ap.rsnFlags) & SAE)) return "sae"
    if (bsses.some(ap => securityOf(ap) === "psk")) return "psk"
    if (bsses.some(ap => (ap.wpaFlags | ap.rsnFlags) & (OWE | OWE_TM))) return "owe"
    return "open"
}
// Whether a single BSS is actually compatible with a group's chosen security —
// used both to pick which BSS's signal to report here and, in nm.js, to pick
// which BSS to connect to. A transition (PSK+SAE) BSS satisfies "sae".
export function apSupports(ap, security) {
    const all = ap.wpaFlags | ap.rsnFlags
    if (security === "unsupported") return securityOf(ap) === "unsupported"
    if (security === "sae") return Boolean(all & SAE)
    if (security === "psk") return securityOf(ap) === "psk"
    if (security === "owe") return Boolean(all & (OWE | OWE_TM))
    return securityOf(ap) === "open"
}

export function wifiNetworks(snap) {
    const saved = savedWifi(snap)
    const known = new Set(saved.map(c => c.ssid))
    const active = new Set(saved.filter(c => c.state === "activated").map(c => c.ssid))
    const activating = new Set(saved.filter(c => c.state === "activating").map(c => c.ssid))
    const grouped = new Map()
    for (const ap of snap.accessPoints) {
        if (!ap.ssid) continue
        if (!grouped.has(ap.ssid)) grouped.set(ap.ssid, [])
        grouped.get(ap.ssid).push(ap)
    }
    return [...grouped.entries()].map(([ssid, bsses]) => {
        // Signal/bars come from the strongest BSS that actually offers the
        // group's security — the strongest BSS overall can be a weaker-security
        // sighting (e.g. an SAE-only AP next to a stronger open one), which
        // would be the wrong one to connect to.
        const security = groupSecurity(bsses)
        const best = bsses.filter(ap => apSupports(ap, security)).reduce((a, b) => b.strength > a.strength ? b : a)
        return {
            ssid, signal: best.strength, bars: Math.max(1, Math.min(4, Math.ceil(best.strength / 25))),
            security, known: known.has(ssid), active: active.has(ssid), activating: activating.has(ssid),
        }
    }).sort((a, b) => b.active - a.active || b.activating - a.activating || b.known - a.known || b.signal - a.signal || a.ssid.localeCompare(b.ssid))
}

export const isProton = connection => connection.id.startsWith("ProtonVPN ")
export function vpnConnections(snap, mode = PROTON_MODE) {
    return snap.connections.filter(c => VPN_TYPES.has(c.type)).map(c => ({
        uuid: c.uuid, name: c.id, state: c.state || "off", iface: c.iface, proton: isProton(c),
        control: isProton(c) && mode === "app" ? "app" : "switch",
    })).sort((a, b) => (b.state === "activated") - (a.state === "activated")
        || (b.state === "activating") - (a.state === "activating") || a.name.localeCompare(b.name))
}

export function networkView(snap, { protonApp = false, mode = PROTON_MODE } = {}) {
    if (!snap.running) return { running: false }
    const vpn = vpnConnections(snap, mode)
    return {
        running: true,
        wifi: { enabled: snap.wifiEnabled, available: snap.wifiDevices.length > 0, networks: snap.wifiDevices.length ? wifiNetworks(snap) : [] },
        wired: snap.wired,
        vpn,
        proton: protonApp ? { mode, active: vpn.some(v => v.proton && v.state === "activated") } : null,
    }
}

// UTF-8 length without TextEncoder, which QML's V4 engine lacks.
function utf8Length(text) {
    let bytes = 0
    for (const char of text) {
        const code = char.codePointAt(0)
        bytes += code < 0x80 ? 1 : code < 0x800 ? 2 : code < 0x10000 ? 3 : 4
    }
    return bytes
}
function validSsid(ssid) {
    // Bounded by code points, not UTF-8 bytes: the display form of a non-UTF-8
    // SSID (libnm's escaped rendering) maps each raw byte to one code point, so
    // a valid 32-byte SSID can display as up to 32 code points regardless of
    // how many bytes each one would take if re-encoded.
    if (typeof ssid !== "string" || !ssid || /[\0\r\n]/.test(ssid) || [...ssid].length > 32) throw new Error("Invalid network name")
    return ssid
}
function validPsk(psk) {
    if (typeof psk !== "string" || !(/^[\x20-\x7e]{8,63}$/.test(psk) || /^[0-9a-fA-F]{64}$/.test(psk)))
        throw new Error("The password must be 8–63 characters, or 64 hexadecimal digits")
    return psk
}
function validSae(psk) {
    if (typeof psk !== "string" || !psk || /[\0\r\n]/.test(psk)) throw new Error("The password must not be empty or contain line breaks")
    if (utf8Length(psk) > 256) throw new Error("The password is too long")
    return psk
}
export function connectPlan(snap, request) {
    const ssid = validSsid(request.ssid)
    const net = wifiNetworks(snap).find(n => n.ssid === ssid)
    if (!net) throw new Error("That network is no longer in range")
    const supplied = request.psk === "" || request.psk === undefined || request.psk === null ? null : request.psk
    const profiles = savedWifi(snap).filter(c => c.ssid === ssid)
    const saved = profiles.map(c => c.uuid)
    // A saved profile needs no security handling here, whatever made it (Advanced… included);
    // the one in use or connecting wins over older duplicates.
    const current = profiles.find(c => c.state === "activated") || profiles.find(c => c.state === "activating") || profiles[0]
    if (current && supplied === null) return { kind: "activate", uuid: current.uuid }
    if (net.security === "unsupported") throw new Error("Enterprise and WEP networks are not supported here; use Advanced…")
    if (net.security === "open" || net.security === "owe") {
        // Open/OWE take no password. A supplied one is refused rather than
        // silently dropped: connecting anyway would be an unauthenticated
        // downgrade from whatever the user thought they were typing a password
        // for, and it would delete the old, still-trusted saved profiles.
        if (supplied !== null) throw new Error("This network does not use a password")
        return { kind: "add", ssid, psk: null, keyMgmt: net.security === "owe" ? "owe" : null, replace: saved }
    }
    if (supplied === null) throw new Error("Enter the network password")
    const psk = net.security === "sae" ? validSae(supplied) : validPsk(supplied)
    return { kind: "add", ssid, psk, keyMgmt: net.security === "sae" ? "sae" : "wpa-psk", replace: saved }
}
export function forgetPlan(snap, ssid) {
    const name = validSsid(ssid)
    const uuids = savedWifi(snap).filter(c => c.ssid === name).map(c => c.uuid)
    if (!uuids.length) throw new Error("That network is not saved")
    return uuids
}
export function vpnPlan(snap, request, mode = PROTON_MODE) {
    if (typeof request.active !== "boolean") throw new Error("Expected an on/off value")
    const connection = snap.connections.find(c => c.uuid === request.uuid)
    if (!connection) throw new Error("That connection no longer exists")
    if (!VPN_TYPES.has(connection.type)) throw new Error("That connection is not a VPN")
    if (isProton(connection) && mode === "app") throw new Error("Use the Proton VPN app for this connection")
    return { uuid: connection.uuid, active: request.active }
}

const reasons = {
    NO_SECRETS: "Wrong password", LOGIN_FAILED: "Wrong password",
    CONNECT_TIMEOUT: "The network did not answer in time", SERVICE_START_TIMEOUT: "The VPN service did not start in time",
    DEVICE_DISCONNECTED: "The Wi-Fi device disconnected", CONNECTION_REMOVED: "The connection was removed",
    DEPENDENCY_FAILED: "A connection this one depends on failed",
}
export const failureMessage = name => {
    if (Object.prototype.hasOwnProperty.call(reasons, name)) return reasons[name]
    return name === undefined || name === null ? "Connection failed" : `Connection failed (${String(name).toLowerCase().replace(/_/g, " ")})`
}
