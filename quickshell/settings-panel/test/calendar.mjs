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
// The banner's two sources: a sign-in failure must survive a failed and a successful calendar read.
const R = 'Could not read calendars: keyring locked'
const W = 'Sign-in rejected: wrong password'
let banner = { problem: '', shownRead: '' }
banner = C.nextProblem(W, banner.shownRead, '')                       // sign-in fails (write error)
assert.deepEqual(banner, { problem: W, shownRead: '' })
banner = C.nextProblem(banner.problem, banner.shownRead, R)           // periodic read fails
assert.deepEqual(banner, { problem: W, shownRead: '' }, 'a read failure never hides a sign-in failure')
banner = C.nextProblem(banner.problem, banner.shownRead, '')          // periodic read succeeds
assert.deepEqual(banner, { problem: W, shownRead: '' }, 'a read recovery never clears a sign-in failure')
// A plain read error, then recovery.
banner = C.nextProblem('', '', R)
assert.deepEqual(banner, { problem: R, shownRead: R })
banner = C.nextProblem(banner.problem, banner.shownRead, R)           // still failing: unchanged
assert.deepEqual(banner, { problem: R, shownRead: R })
banner = C.nextProblem(banner.problem, banner.shownRead, '')          // recovers: cleared
assert.deepEqual(banner, { problem: '', shownRead: '' })
// A write error that lands over a shown read error stays after the read recovers.
banner = C.nextProblem('', '', R)
banner = C.nextProblem(W, banner.shownRead, '')
assert.deepEqual(banner, { problem: W, shownRead: '' })
banner = C.nextProblem(banner.problem, banner.shownRead, '')
assert.deepEqual(banner, { problem: W, shownRead: '' })
console.log('calendar: ok')
