import assert from 'node:assert/strict'
import * as a from '../about.mjs'

const iso = '2025-08-14T12:03:26+0200'
const log = `[${iso}] [PACMAN] Running pacman
[2026-01-03T09:02:00+0100] [PACMAN] starting full system upgrade
[2026-01-03T09:03:00+0100] [ALPM] transaction completed
[2026-01-05T11:15:00+0100] [PACMAN] starting full system upgrade
[2026-01-05T11:16:00+0100] [ALPM] transaction completed
`
assert.equal(a.installedFromPacmanLog(log.split('\n')[0]), new Date(iso).toISOString())
assert.equal(a.installedFromPacmanLog('broken'), null)
assert.equal(a.installedFromPacmanLog('[not-a-date] hello'), null)
assert.equal(a.lastFullUpgrade(log), '2026-01-05T10:15:00.000Z')
assert.equal(a.lastFullUpgrade('nothing'), null)
for (const suffix of [
    '[2026-01-06T10:00:00+0100] [PACMAN] starting full system upgrade\n', // declined
    '[2026-01-06T10:00:00+0100] [PACMAN] starting full system upgrade\n[2026-01-06T10:01:00+0100] [ALPM] transaction started\n', // failed
    '[2026-01-06T10:00:00+0100] [PACMAN] starting full system upgrade\n[2026-01-06T10:00:01+0100] [PACMAN] nothing to do\n',
]) {
    assert.equal(a.lastFullUpgrade(log + suffix), '2026-01-05T10:15:00.000Z')
    assert.equal(a.lastFullUpgrade(suffix), null)
}
assert.equal(a.lastFullUpgrade(log + '[2026-01-06T10:00:00+0100] [PACMAN] starting full system upgrade\n[2026-01-07T10:00:00+0100] [PACMAN] starting full system upgrade\n[2026-01-07T10:01:00+0100] [ALPM] transaction completed'), '2026-01-07T09:00:00.000Z')
assert.equal(a.lastFullUpgrade('[2026-01-06T10:01:00+0100] [ALPM] transaction completed'), null)
// A declined upgrade followed by an unrelated install is not a completed upgrade.
assert.equal(a.lastFullUpgrade('[2026-01-06T10:00:00+0100] [PACMAN] starting full system upgrade\n[2026-01-06T12:00:00+0100] [PACMAN] Running \'pacman -S jq\'\n[2026-01-06T12:00:01+0100] [ALPM] transaction completed'), null)
assert.equal(a.osName('NAME="Example Linux"\nPRETTY_NAME="Example Rolling"'), 'Example Rolling')
assert.equal(a.osName("NAME='Example Linux'"), 'Example Linux')
assert.equal(a.osName(''), '')
const cpu = 'processor : 0\nmodel name : Intel(R) Core(TM) i5-8600 CPU @ 3.10GHz\ncpu cores : 6\nprocessor : 1\n'
assert.deepEqual(a.cpuInfo(cpu), {name:'Intel Core i5-8600', cores:6, threads:2})
assert.equal(a.cpuInfo('model name : AMD Ryzen 7 5800X 8-Core Processor').name, 'AMD Ryzen 7 5800X')
assert.deepEqual(a.cpuInfo(''), {name:'', cores:null, threads:null})
assert.equal(a.memoryGB('MemTotal: 32768000 kB'), 32)
assert.equal(a.memoryGB(''), null)
assert.deepEqual(a.gpus('01:00.0 "VGA compatible controller" "NVIDIA Corporation" "GA104 [GeForce RTX 3070]" -r01\n00:02.0 "Display controller" "Intel Corporation" "UHD Graphics"\n00:03.0 "3D controller" "Advanced Micro Devices, Inc. [AMD/ATI]" "Navi [Radeon RX 6600]"\n00:04.0 "Audio device" "NVIDIA Corporation" "Audio"'), ['NVIDIA GeForce RTX 3070','Intel UHD Graphics','AMD Radeon RX 6600'])
assert.deepEqual(a.gpus(''), [])
for (const [input, output] of [['ASUSTeK COMPUTER INC.','ASUS'],['Micro-Star International Co., Ltd.','MSI'],['Gigabyte Technology Co., Ltd.','Gigabyte'],['LENOVO','Lenovo'],['Dell Inc.','Dell'],['Hewlett-Packard','HP'],['HP','HP'],['Example Corporation','Example'],['Example Co., Ltd.','Example'],['Example Ltd.,','Example']]) assert.equal(a.vendorShort(input),output)
for (const productName of ['', 'System manufacturer','System Product Name','To be filled by O.E.M.','Default string','Not Applicable','Standard PC'])
    assert.deepEqual(a.machine({productName,boardVendor:'ASUSTeK COMPUTER INC.',boardName:'PRIME B660-A'}),{label:'Motherboard',value:'ASUS PRIME B660-A'})
assert.deepEqual(a.machine({sysVendor:'LENOVO',productName:'21CBCTO1WW',productVersion:'ThinkPad X1 Carbon Gen 10'}),{label:'Model',value:'Lenovo ThinkPad X1 Carbon Gen 10'})
// A placeholder vendor with the board name copied into product_name is still a motherboard.
assert.deepEqual(a.machine({sysVendor:'System manufacturer',productName:'PRIME B660-A',boardVendor:'ASUSTeK COMPUTER INC.',boardName:'PRIME B660-A'}),{label:'Motherboard',value:'ASUS PRIME B660-A'})
assert.deepEqual(a.machine({sysVendor:'Micro-Star International Co., Ltd.',productName:'MS-7C02',boardVendor:'Micro-Star International Co., Ltd.',boardName:'B450 TOMAHAWK MAX (MS-7C02)'}),{label:'Motherboard',value:'MSI B450 TOMAHAWK MAX (MS-7C02)'})
assert.deepEqual(a.machine({sysVendor:'Dell Inc.',productName:'Example Board',boardVendor:'Example Corporation',boardName:'Example Board'}),{label:'Motherboard',value:'Example Example Board'})
assert.deepEqual(a.machine({sysVendor:'LENOVO',productName:'21CBCTO1WW',productVersion:'Default string'}),{label:'Model',value:'Lenovo 21CBCTO1WW'})
assert.deepEqual(a.machine({sysVendor:'System manufacturer',productName:'Example Desktop',boardVendor:'Example Corporation',boardName:'Example Board'}),{label:'Motherboard',value:'Example Example Board'})
assert.deepEqual(a.machine({sysVendor:'Example Corporation',productName:'Default string',boardVendor:'Example Corporation',boardName:'Example Board'}),{label:'Motherboard',value:'Example Example Board'})
assert.equal(a.machine({}),null)
for (const [s,t] of [[0,'0 m'],[2700,'45 m'],[28260,'7 h 51 m'],[183600,'2 d 3 h']]) assert.equal(a.formatUptime(s),t)
assert.equal(a.formatUptime(null),'')
for (const [s,t] of [[2700,'45m'],[28260,'7h 51m'],[183600,'2d 3h']]) assert.equal(a.formatUptime(s,true),t)
const date = (y,m,d,h=12,min=0) => new Date(y,m-1,d,h,min)
const now = date(2026,10,2)
assert.equal(a.formatInstalled(date(2025,11,2),now),'2 November 2025 · 11 months ago')
assert.equal(a.formatInstalled(date(2026,10,1),now),'1 October 2026 · less than a month ago')
assert.equal(a.formatInstalled(date(2026,9,2),now),'2 September 2026 · 1 month ago')
assert.equal(a.formatInstalled(date(2025,10,2),now),'2 October 2025 · 1 year ago')
assert.equal(a.formatInstalled(date(2025,7,2),now),'2 July 2025 · 1 year, 3 months ago')
assert.equal(a.formatInstalled(date(2024,10,2),now),'2 October 2024 · 2 years ago')
assert.equal(a.formatInstalled(null,now),'')
assert.equal(a.formatLastUpgrade(date(2026,10,2,11,15),now),'Today, 11:15')
assert.equal(a.formatLastUpgrade(date(2026,10,1,9,2),now),'Yesterday, 09:02')
for (const days of [2,3,30]) assert.equal(a.formatLastUpgrade(new Date(now.getFullYear(),now.getMonth(),now.getDate()-days),now),days+' days ago')
assert.equal(a.formatLastUpgrade(date(2025,11,2),now),'2 November 2025')
assert.equal(a.formatLastUpgrade('bad',now),'')
assert.deepEqual(a.storageGB(999e9,199e9),{used:199,total:999,fraction:199/999})
assert.equal(a.storageGB(0,0),null)
assert.equal(a.storageGB(null,null),null)
assert.equal(a.sessionName('Hyprland:GNOME','wayland'),'Hyprland on Wayland')
assert.equal(a.sessionName('Example','x11'),'Example on X11')
assert.equal(a.sessionName(null,null),'')
console.log('ok: about')

// Exercise the real QML controller's methods, rather than the view's fixture select().
const fs = await import('node:fs')
const vm = await import('node:vm')
const shell = fs.readFileSync(new URL('../shell.qml', import.meta.url), 'utf8')
function functionBody(name) {
    const start = shell.indexOf('function ' + name + '(')
    return shell.slice(start, shell.indexOf('\n    function ', start + 1))
}
const context = {
    opened:true,busy:false,catalog:{rows:[{id:'one'}]},category:'appearance',reader:{running:false},
    configDir:'/fixture/.config',liveTimer:{stop(){}},query:'',about:null,network:null,refreshCalls:0,
}
vm.createContext(context)
vm.runInContext(functionBody('refresh'),context)
context.refresh()
assert.equal(JSON.parse(context.reader.command[2]).about,'summary')
context.reader.running = false; context.category = 'about'; context.refresh()
assert.equal(JSON.parse(context.reader.command[2]).about,'full')
context.refresh = () => context.refreshCalls++
vm.runInContext(functionBody('select'),context)
context.select('about'); assert.equal(context.refreshCalls,1)
context.about = {session:null}; context.select('about'); assert.equal(context.refreshCalls,1,'null full data still counts as read')
// The reader callback merges summaries and catches a page selected mid-read.
const callbackStart = shell.indexOf('        onExited: code => {',shell.indexOf('        id: reader'))
const callback = shell.slice(callbackStart + '        onExited: code => {'.length, shell.indexOf('\n        }\n    }', callbackStart))
const root = {readReply:JSON.stringify({ok:true,values:{},about:{user:'alex',uptimeSeconds:60}}),
    about:{session:'Example on Wayland',cpu:{name:'Example'}},values:{},readerAboutFull:false,readerStartup:false,
    category:'about',queue:[],closing:false,problem:'',startedAt:Date.now(),refresh:()=>context.refreshCalls++}
vm.runInNewContext('(function () {'+callback+'})()', {root,console:{info(){}}})
assert.equal(root.about.cpu.name,'Example','a summary preserves full fields')
assert.equal(root.about.uptimeSeconds,60)
assert.equal(context.refreshCalls,1,'an already-read About page does not loop')
root.about = null
vm.runInNewContext('(function () {'+callback+'})()', {root,console:{info(){}}})
assert.equal(context.refreshCalls,2,'selecting About mid-summary queues the full read')
root.readerAboutFull = true; root.readReply = JSON.stringify({ok:true,values:{},about:{session:null,cpu:null}})
vm.runInNewContext('(function () {'+callback+'})()', {root,console:{info(){}}})
assert.equal(root.about.cpu,null,'a full reply replaces stale full fields')
console.log('ok: about controller')
