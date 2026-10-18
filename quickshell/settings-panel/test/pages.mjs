import assert from 'node:assert/strict'
import * as pages from '../pages.mjs'

const categories = [
    {id: 'a', title: 'Alpha', group: 'look', sections: [
        {id: 'one', title: 'One', footer: 'Note', actions: [{label: 'Go', action: 'waybar'}]},
        {id: 'two', title: 'Two'}]},
    {id: 'b', title: 'Beta', group: 'look', sections: [{id: 'x', title: 'X'}]},
    {id: 'c', title: 'Gamma', group: 'system', sections: [{id: 'y', title: 'Y'}]},
]
const rows = [
    {id: 'a.2', category: 'a', section: 'two', kind: 'toggle'},
    {id: 'a.1', category: 'a', section: 'one', kind: 'toggle'},
    {id: 'a.loose', category: 'a', kind: 'toggle'},
    {id: 'b.1', category: 'b', section: 'x', kind: 'toggle'},
    {id: 'c.1', category: 'c', section: 'y', kind: 'slider', min: 1, max: 10, step: 1, invert: true, ends: ['Slow', 'Fast'], dependsOn: 'c.0'},
]

// A gap opens only where the group changes.
assert.deepEqual(pages.navEntries(categories).map(c => c.gapBefore), [false, false, true])
assert.equal(pages.navEntries(categories)[0].title, 'Alpha', 'entries keep every category field')

// A page: declared section order (not row order), footers and actions kept, loose rows last.
let sections = pages.pageSections(categories, rows.filter(r => r.category === 'a'), false)
assert.deepEqual(sections.map(s => [s.key, s.title, s.rows.map(r => r.id)]), [
    ['a/one', 'One', ['a.1']], ['a/two', 'Two', ['a.2']], ['a/', '', ['a.loose']]])
assert.equal(sections[0].footer, 'Note')
assert.deepEqual(sections[0].actions, [{label: 'Go', action: 'waybar'}])

// A search: sidebar order, "Page › Section" captions, no footers or actions.
sections = pages.pageSections(categories, [rows[3], rows[1]], true)
assert.deepEqual(sections.map(s => [s.title, s.footer, s.actions.length]), [['Alpha › One', '', 0], ['Beta › X', '', 0]])
assert.deepEqual(pages.pageSections(categories, [], true), [])
// A category without declared sections (the QML test fixture) still draws its rows.
assert.deepEqual(pages.pageSections([{id: 'q', title: 'Q'}], [{id: 'q.1', category: 'q'}], false).map(s => [s.key, s.title]), [['q/', '']])

// A section may name the device its heading follows; searching drops it with the rest of the page chrome.
assert.ok(pages.CUSTOM_PAGES.includes('sound'))
const titled = [{id: 's', title: 'Sound', group: 'hardware', sections: [{id: 'out', title: 'Output', titleFrom: 'sound-output'}, {id: 'plain', title: 'Plain'}]}]
const titledRows = [{id: 's.1', category: 's', section: 'out', kind: 'toggle'}, {id: 's.2', category: 's', section: 'plain', kind: 'toggle'}]
assert.deepEqual(pages.pageSections(titled, titledRows, false).map(s => s.titleFrom), ['sound-output', ''])
assert.deepEqual(pages.pageSections(titled, titledRows, true).map(s => s.titleFrom), ['', ''])
assert.deepEqual(pages.validateCatalog({categories: titled, rows: titledRows}), [])

// mirror is its own inverse, and a no-op without invert.
assert.equal(pages.mirror(rows[4], 3), 8)
assert.equal(pages.mirror(rows[4], pages.mirror(rows[4], 3)), 3)
assert.equal(pages.mirror({min: 0, max: 10}, 3), 3)

// dependencyOff only when the named toggle reads false: unknown or still loading is not "off".
assert.equal(pages.dependencyOff(rows[4], {'c.0': {value: false}}), true)
assert.equal(pages.dependencyOff(rows[4], {'c.0': {value: true}}), false)
assert.equal(pages.dependencyOff(rows[4], {}), false)
assert.equal(pages.dependencyOff(rows[0], {}), false)

// validateCatalog: a valid catalog passes, and each rule fails on its own.
const good = {categories, rows: [rows[0], rows[1], rows[3], {id: 'c.0', category: 'c', section: 'y', kind: 'toggle'}, rows[4]]}
assert.deepEqual(pages.validateCatalog(good), [])
const broken = mutate => { const c = structuredClone(good); mutate(c); return pages.validateCatalog(c).join('\n') }
assert.match(broken(c => { c.categories[0].group = 'nope' }), /unknown group/)
assert.match(broken(c => {
    c.categories.push({id: 'd', title: 'D', group: 'look', sections: [{id: 'z', title: 'Z'}]})
    c.rows.push({id: 'd.1', category: 'd', section: 'z', kind: 'toggle'})
}), /group look is split/)
assert.match(broken(c => { c.rows[0].section = 'missing' }), /unknown section/)
assert.match(broken(c => { c.rows.push({id: 'a.1', category: 'a', section: 'one', kind: 'toggle'}) }), /duplicate id/)
assert.match(broken(c => { c.categories[1].sections.push({id: 'empty', title: 'Empty'}) }), /empty section/)
assert.match(broken(c => { c.categories[0].sections[0].titleFrom = 'x' }), /bad titleFrom/)
assert.match(broken(c => { c.categories[0].sections[0].actions = [{label: 'Bad', action: 'rm'}] }), /bad action/)
assert.match(broken(c => { c.rows.find(r => r.id === 'c.1').dependsOn = 'a.1' }), /dependsOn/)
assert.match(broken(c => { c.rows.find(r => r.id === 'c.1').ends = ['One'] }), /ends/)
assert.match(broken(c => { c.rows.find(r => r.id === 'a.1').invert = true }), /invert/)
assert.match(broken(c => { c.categories[2].sections = []; c.rows = c.rows.filter(r => r.category !== 'c') }), /no sections/)
assert.match(broken(c => { c.rows[0].category = 'zz' }), /unknown category/)
// A custom page may have no sections, and a row its view draws itself (inView) needs none.
assert.deepEqual(pages.validateCatalog({categories: [{id: 'network', title: 'N', group: 'connectivity', sections: []}],
    rows: [{id: 'network.wifi', category: 'network', kind: 'toggle', inView: true}]}), [])
// Footer pages neither consume nav space nor split the visible groups.
const footer = {id:'about',title:'About',group:'system',placement:'footer',sections:[]}
assert.deepEqual(pages.navEntries([categories[0], footer, categories[1], categories[2]]).map(c => [c.id,c.gapBefore]), [['a',false],['b',false],['c',true]])
assert.deepEqual(pages.validateCatalog({categories:[footer],rows:[]}),[])
assert.match(pages.validateCatalog({categories:[{...footer,placement:'header'}],rows:[]}).join('\n'),/placement/)
console.log('ok: pages')
