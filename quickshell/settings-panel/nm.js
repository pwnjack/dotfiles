import GLib from "gi://GLib"
import Gio from "gi://Gio"
import NM from "gi://NM"
import { failureMessage, apSupports, groupSecurity } from "./network.mjs"

// The only libnm user. It returns plain objects so everything else is testable
// without NetworkManager, and it waits for real activation, not just the D-Bus reply.
for (const [method, finish] of [["add_and_activate_connection_async", "add_and_activate_connection_finish"],
    ["activate_connection_async", "activate_connection_finish"], ["deactivate_connection_async", "deactivate_connection_finish"],
    ["dbus_set_property", "dbus_set_property_finish"]]) Gio._promisify(NM.Client.prototype, method, finish)
Gio._promisify(NM.RemoteConnection.prototype, "delete_async", "delete_finish")
Gio._promisify(NM.DeviceWifi.prototype, "request_scan_async", "request_scan_finish")

let client = null
// Test-only seam: nm-adapter.js swaps in a fake client so the adapter is
// testable without a real NetworkManager. Never called from panel code.
export function useClientForTests(fakeClient) { client = fakeClient }
function nm() {
    if (!client) client = NM.Client.new(null) // 7.5 ms, synchronous; the helper lives for one request.
    return client
}
const ssidText = bytes => bytes ? NM.utils_ssid_to_utf8(bytes.get_data()) : ""
const wifiDevices = () => nm().get_devices().filter(d => d instanceof NM.DeviceWifi)
function stateName(state) {
    if (state === NM.ActiveConnectionState.ACTIVATED) return "activated"
    if (state === NM.ActiveConnectionState.ACTIVATING) return "activating"
    return null
}

export function nmSnapshot() {
    let c
    try { c = nm() } catch (_) { return { running: false } }
    if (!c.get_nm_running()) return { running: false }
    const devices = c.get_devices()
    const wifi = devices.filter(d => d instanceof NM.DeviceWifi)
    const active = new Map(c.get_active_connections().map(a => [a.get_uuid(), a]))
    return {
        running: true,
        wifiEnabled: c.wireless_get_enabled(),
        wifiDevices: wifi.map(d => ({ iface: d.get_iface() })),
        accessPoints: wifi.flatMap(d => d.get_access_points().map(ap => ({
            ssid: ssidText(ap.get_ssid()), strength: ap.get_strength(),
            flags: ap.get_flags(), wpaFlags: ap.get_wpa_flags(), rsnFlags: ap.get_rsn_flags(),
            iface: d.get_iface(),
        }))),
        wired: devices.filter(d => d instanceof NM.DeviceEthernet).map(d => {
            const ip = d.get_ip4_config()
            const address = ip?.get_addresses()[0]
            return { iface: d.get_iface(), carrier: d.get_carrier(), speed: d.get_speed(),
                ip4: address ? `${address.get_address()}/${address.get_prefix()}` : null, gateway: ip?.get_gateway() || null }
        }),
        connections: c.get_connections().map(r => {
            const a = active.get(r.get_uuid())
            const wireless = r.get_setting_wireless()
            return { uuid: r.get_uuid(), id: r.get_id(), type: r.get_connection_type(),
                ssid: wireless ? ssidText(wireless.get_ssid()) : null,
                state: a ? stateName(a.get_state()) : null, iface: a?.get_devices()[0]?.get_iface() || null }
        }),
    }
}

const reasonName = reason => Object.keys(NM.ActiveConnectionStateReason).find(key => NM.ActiveConnectionStateReason[key] === reason) || "UNKNOWN"
// Resolves once the connection is really up; rejects with a readable reason.
// 45s: shorter than panel-request.sh's 60s flock wait (the add/delete calls
// around this add to that same lock hold time, so a slow connect must not push
// the total past it and starve every other request) and longer than NM's own
// DHCP timeout.
export function settled(active, timeoutMs = 45000) {
    return new Promise((resolve, reject) => {
        let stateHandler = 0, removedHandler = 0, timer = 0, sawActivating = false
        const finish = error => {
            if (stateHandler) active.disconnect(stateHandler)
            if (removedHandler) nm().disconnect(removedHandler)
            if (timer) GLib.source_remove(timer)
            stateHandler = removedHandler = timer = 0
            if (error) reject(error); else resolve()
        }
        const check = (state, reason) => {
            if (state === NM.ActiveConnectionState.ACTIVATED) finish()
            else if (state === NM.ActiveConnectionState.DEACTIVATED) finish(new Error(failureMessage(reasonName(reason))))
            else if (state === NM.ActiveConnectionState.ACTIVATING) sawActivating = true
            // NM can unexport the ActiveConnection instead of ever reporting DEACTIVATED.
            else if (state === NM.ActiveConnectionState.UNKNOWN && sawActivating) finish(new Error(failureMessage("CONNECTION_REMOVED")))
        }
        stateHandler = active.connect("state-changed", (_active, state, reason) => check(state, reason))
        removedHandler = nm().connect("active-connection-removed", (_client, removed) => {
            if (removed === active) finish(new Error(failureMessage("CONNECTION_REMOVED")))
        })
        timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, timeoutMs, () => { timer = 0; finish(new Error(failureMessage("CONNECT_TIMEOUT"))); return GLib.SOURCE_REMOVE })
        // A freshly created ActiveConnection can briefly read UNKNOWN before its
        // state property syncs, and before libnm's own cache even lists it in
        // get_active_connections() - that gap is not evidence NM dropped it, just
        // that its cache has not caught up yet. Reporting it as removed here would
        // race a connection that is actually about to come up; the
        // active-connection-removed signal and the UNKNOWN-after-ACTIVATING check
        // below are what catch a real removal.
        check(active.get_state(), active.get_state_reason())
    })
}
function remote(uuid) {
    const connection = nm().get_connection_by_uuid(uuid)
    if (!connection) throw new Error("That connection no longer exists")
    return connection
}

export async function setWifiEnabled(on) {
    await nm().dbus_set_property(NM.DBUS_PATH, NM.DBUS_INTERFACE, "WirelessEnabled", GLib.Variant.new_boolean(on), -1, null)
}
export async function requestScan() {
    // NM refuses scans that come too soon after the last one; that is not a failure.
    await Promise.all(wifiDevices().map(d => d.request_scan_async(null).catch(error => {
        if (!error.matches?.(NM.DeviceError, NM.DeviceError.NOTALLOWED)) throw error
    })))
}
export async function activate(uuid) {
    const active = await nm().activate_connection_async(remote(uuid), null, null, null)
    try { await settled(active) }
    catch (error) { await deactivate(uuid).catch(() => {}); throw error }
}
// keyMgmt (network.mjs's connectPlan) named by NM.SettingWirelessSecurity's
// own key-mgmt string; group security (network.mjs's apSupports) named by the
// page model. The same compatibility test decides both which BSS a group
// reports here and which BSS addAndActivate actually connects to.
const keyMgmtSecurity = { "wpa-psk": "psk", sae: "sae", owe: "owe" }
// null is a truly open network; anything else must be one of the three the
// panel ever sends — an unrecognized keyMgmt is a bug, not a network to
// silently treat as open.
function securityForKeyMgmt(keyMgmt) {
    if (keyMgmt === null) return "open"
    if (!Object.prototype.hasOwnProperty.call(keyMgmtSecurity, keyMgmt)) throw new Error(`Unknown key management ${keyMgmt}`)
    return keyMgmtSecurity[keyMgmt]
}
function apCompatible(ap, keyMgmt) {
    return apSupports({ flags: ap.get_flags(), wpaFlags: ap.get_wpa_flags(), rsnFlags: ap.get_rsn_flags() }, securityForKeyMgmt(keyMgmt))
}
export async function addAndActivate({ ssid, psk, keyMgmt }) {
    const devices = wifiDevices()
    if (!devices.length) throw new Error("No Wi-Fi device")
    // The same SSID can be seen by more than one Wi-Fi device (or as more than
    // one BSS); pick the strongest sighting that can actually take this
    // connection's security — the strongest sighting overall can be a
    // different, incompatible security (e.g. SAE-only next to a weaker PSK one).
    const sightings = devices.flatMap(device => device.get_access_points()
        .filter(a => ssidText(a.get_ssid()) === ssid).map(ap => ({ device, ap })))
    const candidates = sightings.filter(({ ap }) => apCompatible(ap, keyMgmt))
    if (!candidates.length) throw new Error("That network is no longer in range")
    // The plan was built from a snapshot that can be stale by the time this
    // runs (a scan landed, someone else changed the AP). Re-derive the group's
    // security from what is live right now and refuse rather than connect
    // under a security the caller never agreed to.
    const liveSecurity = groupSecurity(sightings.map(({ ap }) => ({ flags: ap.get_flags(), wpaFlags: ap.get_wpa_flags(), rsnFlags: ap.get_rsn_flags() })))
    if (liveSecurity !== securityForKeyMgmt(keyMgmt)) throw new Error("The network changed; try again")
    const { device, ap } = candidates.sort((a, b) => b.ap.get_strength() - a.ap.get_strength())[0]
    const uuid = NM.utils_uuid_generate()
    const connection = NM.SimpleConnection.new()
    connection.add_setting(new NM.SettingConnection({ id: ssid, uuid, type: "802-11-wireless", autoconnect: true }))
    // The AP's own bytes, not a re-encoding of the display string: a non-UTF-8
    // SSID round-trips lossily through nm_utils_ssid_to_utf8.
    connection.add_setting(new NM.SettingWireless({ ssid: ap.get_ssid(), mode: "infrastructure" }))
    // keyMgmt is "wpa-psk", "sae" or "owe" (network.mjs); a truly open network has none.
    if (keyMgmt) connection.add_setting(new NM.SettingWirelessSecurity(psk !== null ? { key_mgmt: keyMgmt, psk } : { key_mgmt: keyMgmt }))
    // A wrong password, or a rejection of the add-and-activate call itself,
    // must not leave a "Saved" network behind — NM can persist the profile
    // before activation even fails. Go by the uuid we generated, not
    // active.get_connection(): NM can unexport the ActiveConnection before this
    // runs, which makes that getter return null.
    async function cleanupAfterFailure(error) {
        // A profile NM already removed (or never finished registering) by the
        // time this runs is nothing to clean up, not a cleanup failure.
        try { await deleteIfPresent(uuid) }
        catch (deleteError) {
            throw new Error(`${error.message}; removing the new network profile also failed: ${deleteError.message}`)
        }
        throw error
    }
    let active
    try { active = await nm().add_and_activate_connection_async(connection, device, ap.get_path(), null) }
    catch (error) { await cleanupAfterFailure(error) }
    try { await settled(active) }
    catch (error) { await cleanupAfterFailure(error) }
}
export async function deactivate(uuid) {
    const active = nm().get_active_connections().find(a => a.get_uuid() === uuid)
    if (active) await nm().deactivate_connection_async(active, null)
}
// A profile can vanish between the caller's snapshot and this call (someone
// else removed it, or NM auto-removed it): get_connection_by_uuid then misses
// it, or - if it unexports the object mid-call - delete_async itself rejects
// with an "unknown object"/"unknown method" D-Bus error. libnm strips the
// GDBus remote-error prefix on void calls (delete_async included), so
// Gio.DBusError.is_remote_error alone is unreliable; matching the error's own
// domain/code is what actually works, with the remote-name check kept only as
// a fallback path.
function isVanished(error) {
    if (!(error instanceof GLib.Error)) return false
    if (error.matches(Gio.DBusError, Gio.DBusError.UNKNOWN_METHOD) || error.matches(Gio.DBusError, Gio.DBusError.UNKNOWN_OBJECT)) return true
    return Gio.DBusError.is_remote_error(error)
        && ["org.freedesktop.DBus.Error.UnknownObject", "org.freedesktop.DBus.Error.UnknownMethod"].includes(Gio.DBusError.get_remote_error(error))
}
// False when the profile is already gone, never a throw, so no caller has to
// match nm.js's own wording to tell that apart from a real failure.
export async function deleteIfPresent(uuid) {
    const connection = nm().get_connection_by_uuid(uuid)
    if (!connection) return false
    try { await connection.delete_async(null); return true }
    catch (error) {
        if (isVanished(error)) return false
        throw error
    }
}
