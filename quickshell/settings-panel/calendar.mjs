// Calendar page helpers, free of GJS so node can test them.
export const SETUP = '/scripts/calendar/setup.sh'
// The argv that signs in: credentials go on stdin, never here.
export function signInCommand(configDir) { return ['bash', configDir + SETUP, '--sign-in', '--stdin'] }
export function signInInput(appleId, password) {
    if (/[\r\n]/.test(appleId) || /[\r\n]/.test(password)) throw new Error('Line breaks are not allowed')
    if (!appleId.trim() || !password) throw new Error('Enter the Apple ID and the app-specific password')
    return appleId.trim() + '\n' + password + '\n'
}
// toggleHidden(text, name, shown) -> the new options/calendar-hidden text.
export function toggleHidden(text, name, shown) {
    const names = String(text || '').split('\n').map(s => s.trim()).filter(Boolean).filter(n => n !== name)
    if (!shown) names.push(name)
    return names.length ? names.join('\n') + '\n' : ''
}
// The Calendar page's reader may finish after the page was hidden; only a read started under
// the current generation may be applied (the Devices page's rule).
export function fresh(startedGeneration, currentGeneration, shown) {
    return shown && startedGeneration === currentGeneration
}
// calendarStatus through panel-request.sh -> {calendar} or {error}. A lock timeout prints to
// stderr only, and a backend failure replies {"ok":false,"error":...}; either way the
// caller keeps the model it already has.
export function readReply(stdout, stderr, code) {
    let reply = null
    try { reply = JSON.parse(stdout) } catch (_) { /* No reply: the helper failed before answering. */ }
    if (code === 0 && reply && reply.ok === true && reply.calendar) return { calendar: reply.calendar }
    if (reply && reply.error) return { error: String(reply.error) }
    const detail = String(stderr || '').trim().split('\n').pop()
    return { error: detail || `the settings helper exited ${code} without a reply` }
}
// "Last synced 3 min ago" / the failure, from status.json.
export function statusLine(status, now, account) {
    // A stored account with no status yet has never synced.
    if (!status || status.state === 'none') return account ? 'Not synced yet' : 'Not signed in'
    if (status.state === 'failed') return status.message || 'The last sync failed'
    const min = Math.round((now - (status.lastSuccess || now)) / 60)
    return min <= 0 ? 'Synced just now' : `Last synced ${min} min ago`
}
