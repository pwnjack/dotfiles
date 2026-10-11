import assert from 'node:assert/strict'
import * as C from '../calendar.mjs'
const argv = C.signInCommand('/home/u/.config')
assert.deepEqual(argv, ['bash', '/home/u/.config/scripts/calendar/setup.sh', '--sign-in', '--stdin'])
assert.equal(C.signInInput(' me@icloud.com ', 'abcd-efgh'), 'me@icloud.com\nabcd-efgh\n')
assert.ok(!argv.join(' ').includes('abcd-efgh'))
assert.throws(() => C.signInInput('me', 'a\nb'))
assert.throws(() => C.signInInput('', 'x'))
assert.equal(C.toggleHidden('', 'Work', false), 'Work\n')
assert.equal(C.toggleHidden('Work\nHome\n', 'Work', true), 'Home\n')
assert.equal(C.toggleHidden('Work\n', 'Work', true), '')
assert.equal(C.toggleHidden('Work\n', 'Work', false), 'Work\n')
assert.equal(C.statusLine(null, 0), 'Not signed in')
assert.equal(C.statusLine(null, 0, 'me@icloud.com'), 'Not synced yet')
assert.equal(C.statusLine({ state: 'ok', lastSuccess: 1000 }, 1180), 'Last synced 3 min ago')
assert.equal(C.statusLine({ state: 'failed', message: 'Sign-in rejected' }, 0), 'Sign-in rejected')
// The read guard: a read started before the page was hidden, or under an older show, is stale.
assert.equal(C.fresh(3, 3, true), true)
assert.equal(C.fresh(3, 4, true), false, 'hidden and shown again during the read')
assert.equal(C.fresh(3, 3, false), false, 'nothing lands while hidden')
// A usable reply is applied; a lock timeout, an {"ok":false} reply and garbage are errors.
const calendar = { account: 'me@icloud.com', calendars: [], status: null, line: 'Not synced yet' }
assert.deepEqual(C.readReply(JSON.stringify({ ok: true, calendar }), '', 0), { calendar })
assert.deepEqual(C.readReply('', 'Settings are busy; try again.\n', 1), { error: 'Settings are busy; try again.' })
assert.deepEqual(C.readReply(JSON.stringify({ ok: false, error: 'cal.sh is not installed' }), '', 1), { error: 'cal.sh is not installed' })
assert.deepEqual(C.readReply('not json', 'bash: warning\nfatal: keyring locked\n', 1), { error: 'fatal: keyring locked' })
assert.deepEqual(C.readReply('', '', 2), { error: 'the settings helper exited 2 without a reply' })
assert.ok(C.readReply(JSON.stringify({ ok: true, calendar }), '', 1).error, 'a non-zero exit is never applied')
console.log('calendar: ok')
