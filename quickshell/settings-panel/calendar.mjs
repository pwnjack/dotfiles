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
// "Last synced 3 min ago" / the failure, from status.json.
export function statusLine(status, now, account) {
    // A stored account with no status yet has never synced.
    if (!status || status.state === 'none') return account ? 'Not synced yet' : 'Not signed in'
    if (status.state === 'failed') return status.message || 'The last sync failed'
    const min = Math.round((now - (status.lastSuccess || now)) / 60)
    return min <= 0 ? 'Synced just now' : `Last synced ${min} min ago`
}
