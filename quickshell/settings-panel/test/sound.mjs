import assert from 'node:assert/strict'
import * as S from '../sound.mjs'

// The model's three parsers are re-exported so backend.js imports one module.
assert.equal(typeof S.deriveLabel, 'function')
assert.deepEqual(S.parseHidden('a\n b \n\n'), ['a', 'b'])
assert.deepEqual(S.parseNames('a\tTV\n'), { a: 'TV' })

assert.equal(S.validName('  Desk speakers  '), 'Desk speakers', 'trimmed')
assert.equal(S.validName(''), '')
assert.equal(S.validName('x'.repeat(40)), 'x'.repeat(40))
for (const bad of ['a\tb', 'a\nb', 'a\rb', '\tDesk', 'Desk\n', 'Desk\r', 'Desk\t', '\t']) assert.throws(() => S.validName(bad), { message: 'Names cannot contain line breaks or tabs' })
assert.throws(() => S.validName('x'.repeat(41)), { message: 'Names are at most 40 characters' })

assert.equal(S.toggleHidden('', 'a', false), 'a\n')
assert.equal(S.toggleHidden('a\n', 'a', true), '')
assert.equal(S.toggleHidden('a\nb\n', 'a', true), 'b\n')
assert.equal(S.toggleHidden('a\n', 'a', false), 'a\n', 'hiding twice does not duplicate')
assert.equal(S.toggleHidden(S.toggleHidden('', 'a', false), 'a', true), '', 'round trip')

assert.equal(S.setName('', 'b', 'TV'), 'b\tTV\n', 'add')
assert.equal(S.setName('b\tTV\n', 'b', 'Telly'), 'b\tTelly\n', 'replace')
assert.equal(S.setName('b\tTV\n', 'b', ''), '', 'remove leaves nothing')
assert.equal(S.setName('b\tTV\na\tDesk\n', 'b', ''), 'a\tDesk\n', 'remove keeps the others')
assert.equal(S.setName('b\tTV\n', 'a', 'Desk'), 'a\tDesk\nb\tTV\n', 'sorted by node name')
assert.equal(S.setName('', 'a', '   '), '', 'a blank label is a removal')
assert.equal(S.setName('junk line\nb\tTV\n', 'a', 'Desk'), 'a\tDesk\nb\tTV\n', 'unparseable lines are dropped')
assert.throws(() => S.setName('b\tTV\n', '__proto__', 'X'), { message: 'Invalid device name' })
assert.deepEqual(S.parseNames('__proto__\tX\nb\tTV\n'), { b: 'TV' }, 'a __proto__ line is skipped')
console.log('ok: sound names and hidden list helpers')
