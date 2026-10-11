import assert from 'node:assert/strict'
import fs from 'node:fs'
import { registerHooks } from 'node:module'

// Built, not literal: the doctor's path scan would flag fixture files that do not exist.
const autostartUserDir = '~/.config' + '/autostart'
const base = '/fixture/.config'
const catalog = JSON.parse(fs.readFileSync(new URL('../catalog.json', import.meta.url)))
catalog.rows.push({id:'test.option-slider',source:'option',key:'test-slider',kind:'slider',min:10,max:100,step:1})
catalog.rows.push({id:'test.gtk-raw',source:'gtk',key:'gtk-theme',ini:{key:'gtk-theme-name'}})
const files = new Map([
    [base + '/quickshell/settings-panel/catalog.json', JSON.stringify(catalog)],
    ['/fixture/.local/state/hypr/overrides.lua', ''],
    [base + '/hypr/hypridle.conf', '# Keep this comment\ngeneral { ignore_dbus_inhibit = false }\nlistener {\n timeout = 305\n on-timeout = loginctl lock-session\n}\nlistener {\n timeout = 600\n on-timeout = hyprctl dispatch \'hl.dsp.dpms({action = "off"})\'\n}\n'],
    [base + '/hypr/hyprsunset.conf', '# Keep this comment\nmax-gamma = 100\nprofile {\n time = 07:00\n temperature = 6000\n}\nprofile {\n time = 20:00\n temperature = 4000\n}\n'],
    [base + '/swaync/config.json', JSON.stringify({timeout:5,unrelated:{keep:true}})],
    [base + '/hypr/config/hardware/primary.conf', '$monitor =\n'],
    ['/usr/share/icons/Papirus-Dark/index.theme', '[Icon Theme]\nDirectories=16x16/apps\n'],
    ['/usr/share/icons/Bibata-Modern-Classic/index.theme', '[Icon Theme]\nName=Bibata\n'],
    ['/usr/share/themes/Kripton/gtk-3.0/gtk.css', ''],
    ['/usr/share/themes/Adwaita/gtk-3.0/gtk.css', ''],
    ['/usr/share/themes/A$&B/gtk-3.0/gtk.css', ''],
    ['/usr/share/themes/Bad\nTheme/gtk-3.0/gtk.css', ''],
    ['/usr/share/themes/Emacs/gtk-3.0/gtk-keys.css', ''],
    [base + '/gtk-3.0/settings.ini', '[Settings]\ngtk-theme-name=Kripton\ngtk-font-name=Sans 11\n'],
    [base + '/gtk-4.0/settings.ini', '[Settings]\ngtk-theme-name=Kripton\n'],
    [base + '/Kvantum/Carl/Carl.kvconfig', ''],
    ['/usr/share/Kvantum/KvArc/KvArc.kvconfig', ''],
    [base + '/Kvantum/kvantum.kvconfig', '[General]\ntheme=Carl\n'],
    [base + '/mimeapps.list', '[Default Applications]\ninode/directory=kitty-open.desktop\n'],
    ['/etc/locale.conf', 'LANG=en_US.UTF-8\nLC_TIME=it_IT.UTF-8\nLC_NUMERIC=it_IT.UTF-8\nLC_COLLATE=C.UTF-8\n'],
])
const aboutAttributes = new Map()
const unreadableAvatars = new Set()
let aboutCommandsMissing = false, failAboutTail = false
const aboutStreamReads = []
const dirs = new Map([
    ['/usr/share/themes', ['Kripton','Adwaita','NoGtk','Emacs','A$&B','Bad\nTheme']],
    ['/usr/share/themes/Emacs/gtk-3.0', []],
    ['/usr/share/icons', ['Papirus-Dark','Bibata-Modern-Classic']],
    ['/usr/share/icons/Bibata-Modern-Classic/cursors', []],
    [base + '/Kvantum', ['Carl','kvantum.kvconfig']],
    ['/usr/share/Kvantum', ['KvArc']],
])
const gsettings = {'gtk-theme':"'Kripton'",'icon-theme':"'Papirus-Dark'",'color-scheme':"'prefer-dark'",'text-scaling-factor':'1.0','cursor-size':'24','cursor-theme':"'Bibata-Modern-Classic'"}
const appsForType = {
    'inode/directory': [['thunar.desktop','Thunar'],['org.gnome.Nautilus.desktop','Files']],
    'image/png': [['mpv.desktop','mpv'],['image-viewer.desktop','Image Viewer'],['hexed.desktop','Hex Editor']],
    'text/plain': [['nvim.desktop','Neovim']],
}
const supportedTypes = {
    'thunar.desktop':['inode/directory'],
    'mpv.desktop':['image/png','image/jpeg'],
    'image-viewer.desktop':['image/png'],
    'hexed.desktop':['image/png','application/octet-stream'],
    'nvim.desktop':['text/plain'],
}
const mimeDefaults = {'inode/directory':'kitty-open.desktop'}
let failMime = ''
for (const name of ['font','font-gtk','cursortheme','mainmonitor','browser','terminal','editor','codeeditor','filemanager','aurhelper','launchertype','autologin','protonvpn','randomwallpaper']) files.set(`${base}/options/${name}`,name === 'mainmonitor' ? '' : 'enabled\n')
files.set(base+'/options/clock','24h\n')
for (const name of ['cpu','memory','gpu','disk']) files.set(`${base}/options/bar-${name}`, 'always\n')
files.set(base+'/options/bar-network','traffic\n')
files.set(base+'/options/bar-updates','pending\n')
for (const [key, value] of Object.entries({'bar-position':'top','bar-style':'floating','bar-opacity':'50','bar-border':'enabled','bar-output':'','clock-seconds':'disabled','bar-workspaces':'dots','test-slider':'broken'})) files.set(`${base}/options/${key}`, value+'\n')
files.set(base+'/hypr/config/setup/autostart.lua', 'return function(apps)\n    hl.exec_cmd("waybar")\n    hl.exec_cmd("systemctl --user start " .. apps.polkitAgent)\nend\n')
files.set('/etc/xdg/autostart/nm-applet.desktop', '[Desktop Entry]\nType=Application\nName=Network\nExec=nm-applet\n')
files.set('/etc/xdg/autostart/blueman.desktop', '[Desktop Entry]\nType=Application\nName=Blueman Applet\nExec=blueman-applet\n')
files.set('/etc/xdg/autostart/manual.desktop', '[Desktop Entry]\nType=Application\nName=Manual\nExec=manual\n')
files.set(base + '/autostart/arch-update-tray.desktop', '[Desktop Entry]\nType=Application\nName=Arch-Update Systray Applet\nExec=arch-update --tray\n')
files.set(base + '/autostart/manual.desktop', '[Desktop Entry]\nName=Manual\nHidden=true\nComment=written by hand\n')
files.set('/usr/share/applications/firefox.desktop', '[Desktop Entry]\nName=Firefox\nExec=firefox %u\n')
// Installed applications: [id, name, should_show, desktop-file fields]. The last four
// are never offered: no Exec, wrong desktop, hidden from menus, already an XDG entry.
const appInfos = [
    ['firefox.desktop', 'Firefox', true, {Exec: 'firefox %u'}],
    ['nm-applet.desktop', 'Network', true, {Exec: 'nm-applet'}],
    ['noexec.desktop', 'No Exec', true, {}],
    ['kdeonly.desktop', 'KDE only', true, {Exec: 'kdeonly', OnlyShowIn: 'KDE;'}],
    ['notonhypr.desktop', 'Not on Hyprland', true, {Exec: 'notonhypr', NotShowIn: 'Hyprland;'}],
    ['hidden-app.desktop', 'Hidden app', false, {Exec: 'hidden-app'}]]
// Binaries the user manager's PATH resolves; arch-update is deliberately absent.
const execs = new Set()
for (const name of ['nm-applet','blueman-applet','manual']) { files.set('/usr/bin/'+name, ''); execs.add('/usr/bin/'+name) }
// Symbolic links by path: a target string, or null when dangling. Gio follows them like the real thing.
const links = new Map()
const resolveLink = path => { let at = path; for (let depth = 0; links.has(at) && depth < 8; ++depth) { at = links.get(at); if (at === null) return null } return at }
const gioError = (code, message) => Object.assign(new Error(message), {matches: (_domain, wanted) => wanted === code})
dirs.set('/etc/xdg/autostart', ['nm-applet.desktop', 'blueman.desktop', 'manual.desktop'])
dirs.set(base + '/autostart', ['arch-update-tray.desktop', 'manual.desktop'])
let showEnvironment = 'XDG_CURRENT_DESKTOP=Hyprland\nPATH=/usr/local/bin:/usr/bin\n'
const raceOnce = new Set()
let events = [], failingPath = '', failingReadPath = '', failReload = false, failingGsettingsSets = 0, failNextSpawn = ''
// The calendar's keyring account, cal.sh's listing (null: cal.sh fails) and setup.sh's sign-in failure.
let keyringAccount = '', calendarsListing = null, signInError = '', failCalendarRenders = 0
// Shapes copied from `hyprctl getoption -j` on Hyprland 0.56: the value field
// is named after its type, and `set` is only whether the config assigns it.
const hyprOptions = {
    'decoration:blur:enabled': {bool:true,set:true},
    'decoration:shadow:enabled': {bool:false,set:true},
    'general:gaps_in': {css:'4 4 4 4',set:true},
    'input:accel_profile': {str:'[[EMPTY]]',set:false},
    'input:kb_layout': {str:'us',set:true},
    'input:kb_variant': {str:'intl',set:true},
}
// Trimmed from `pactl -f json` on PipeWire 1.6.9. Note `card` is null on the
// real sinks: the card is linked through properties["device.name"].
const pulse = {
    info: {default_sink_name:'alsa_output.analog', default_source_name:'alsa_input.analog'},
    sinks: [
        {name:'alsa_output.analog',description:'Built-in Audio Analog Stereo',card:null,active_port:'analog-output-headphones',properties:{'device.name':'alsa_card.analog'},
         ports:[{name:'analog-output-lineout',description:'Line Out',availability:'not available'},{name:'analog-output-headphones',description:'Headphones',availability:'available'}]},
        {name:'alsa_output.hdmi',description:'GA102 Digital Stereo (HDMI)',card:null,active_port:'hdmi-output-0',properties:{'device.name':'alsa_card.hdmi'},
         ports:[{name:'hdmi-output-0',description:'HDMI / DisplayPort',availability:'available'}]},
    ],
    sources: [
        {name:'alsa_output.analog.monitor',description:'Monitor of Built-in Audio Analog Stereo',monitor_source:'alsa_output.analog',active_port:'analog-output-headphones',ports:[],volume:{}},
        {name:'alsa_input.analog',description:'Built-in Audio Analog Stereo',monitor_source:'',active_port:'analog-input-front-mic',
         ports:[{name:'analog-input-front-mic',description:'Front Microphone',availability:'not available'},{name:'analog-input-rear-mic',description:'Rear Microphone',availability:'not available'}],
         volume:{'front-left':{value_percent:'60%'},'front-right':{value_percent:'64%'}}},
    ],
    cards: [
        {name:'alsa_card.analog',active_profile:'output:analog-stereo+input:analog-stereo',profiles:{
            off:{description:'Off',available:true,sinks:0},
            // Active but reported unavailable: the active profile is always offered.
            'output:analog-stereo+input:analog-stereo':{description:'Analog Stereo Duplex',available:false,sinks:1},
            'output:analog-surround-51':{description:'Analog Surround 5.1 Output',available:false,sinks:1},
            // Available, but it has no sink: choosing it would remove the output these rows describe.
            'input:analog-stereo':{description:'Analog Stereo Input',available:true,sinks:0},
            'output:iec958-stereo':{description:'Digital Stereo (IEC958) Output',available:true,sinks:1}}},
        {name:'alsa_card.hdmi',active_profile:'output:hdmi-stereo',profiles:{'output:hdmi-stereo':{description:'Digital Stereo (HDMI) Output',available:true,sinks:1}}},
    ],
}
// Shape from `hyprctl monitors all -j` on Hyprland 0.56 (trimmed).
const monitorsFixture = [{name:'DP-1',make:'Ancor Communications Inc',model:'ROG PG279Q',width:2560,height:1440,refreshRate:143.998,scale:1,transform:0,disabled:false,
    availableModes:['2560x1440@59.95Hz','2560x1440@144.00Hz','2560x1440@120.00Hz','2560x1440@99.95Hz','2560x1440@84.98Hz','2560x1440@23.97Hz','1024x768@60.00Hz','800x600@60.32Hz','640x480@59.94Hz']}]
let guardArmed = false, failEval = false, failHyprReload = false, stopFails = false, fireOnStop = false, expireOnEval = false
const mockEnv = {XDG_STATE_HOME:'/fixture/.local/state',HYPRLAND_INSTANCE_SIGNATURE:'sig'}
const running = new Set()
const encoder = new TextEncoder()
// Shape produced by nm.js on NetworkManager 1.58 (trimmed from this machine).
const nmState = {
    running: true, wifiEnabled: true, wifiDevices: [{iface:'wlan0'}],
    accessPoints: [{ssid:'Dimensione-E92F',strength:84,flags:1,wpaFlags:0,rsnFlags:392},{ssid:'Cafe',strength:60,flags:0,wpaFlags:0,rsnFlags:0}],
    wired: [{iface:'eno1',carrier:true,speed:1000,ip4:'192.168.1.10/24',gateway:'192.168.1.1'}],
    connections: [
        {uuid:'u-old',id:'Dimensione-E92F',type:'802-11-wireless',ssid:'Dimensione-E92F',state:null,iface:null},
        {uuid:'u-proton',id:'ProtonVPN IT#113',type:'wireguard',ssid:null,state:'activated',iface:'proton0'},
        {uuid:'u-kill',id:'pvpn-killswitch-ipv6',type:'dummy',ssid:null,state:'activated',iface:'ipv6leakintrf0'}],
}
let nmCalls = [], nmFailAdd = '', nmFailRemove = new Set(), nmMissingRemove = new Set()
const nmMock = {
    nmSnapshot: () => structuredClone(nmState),
    setWifiEnabled: async on => { nmCalls.push(['wifi', on]); nmState.wifiEnabled = on },
    requestScan: async () => { nmCalls.push(['scan']) },
    activate: async uuid => { nmCalls.push(['activate', uuid]) },
    addAndActivate: async plan => { nmCalls.push(['add', plan.ssid, plan.psk, plan.keyMgmt]); if (nmFailAdd) throw new Error(nmFailAdd) },
    deactivate: async uuid => { nmCalls.push(['deactivate', uuid]) },
    removeConnections: async uuids => {
        nmCalls.push(['remove', ...uuids])
        // Mirrors nm.js's real contract: an already-gone uuid is reported
        // structurally, never thrown.
        const missing = []
        for (const uuid of uuids) {
            if (nmMissingRemove.has(uuid)) { missing.push(uuid); continue }
            if (nmFailRemove.has(uuid)) throw new Error(`Cannot remove ${uuid}`)
        }
        return { missing }
    },
}
let dbusCalls = [], dbusDeny = false
let dbusLocale = ['LANG=en_US.UTF-8','LC_TIME=it_IT.UTF-8','LC_NUMERIC=it_IT.UTF-8','LC_COLLATE=C.UTF-8']
let localtimeLink = '/usr/share/zoneinfo/Europe/Rome'
let localtimeMissing = false
const dbusMock = {
    getProperty: async (_name, _path, _iface, property) => property === 'Locale' ? dbusLocale.slice() : ({NTP: true, NTPSynchronized: false}[property]),
    callSystem: async (_name, _path, _iface, method, signature, args, options = {}) => {
        if (method === 'ListTimezones') return [['Europe/Rome', 'America/New_York', 'America/Argentina/Buenos_Aires']]
        dbusCalls.push([method, signature, args, options.interactive === true])
        if (dbusDeny) throw new Error('Authentication was cancelled; nothing changed.')
        return []
    },
}
globalThis.settingsMocks = {
    GLib: {
        get_user_name: () => "alex", get_real_name: () => "Alex Example", get_host_name: () => "workstation",
        SeekType: {SET:0,END:2},
        get_home_dir: () => '/fixture', get_user_config_dir: () => base, Error: class extends Error {},
        mkdir_with_parents: () => 0,
        file_read_link: path => {
            if (path !== '/etc/localtime') return null
            if (localtimeMissing) throw new Error('No such file: '+path)
            return localtimeLink
        },
        getenv: name => mockEnv[name] ?? null,
        get_user_runtime_dir: () => '/run/user/1000',
        find_program_in_path: name => (aboutCommandsMissing && name === 'lspci') || name === 'missing-app' || name === 'arch-update' ? null : name,
        SpawnFlags: {SEARCH_PATH:1,STDOUT_TO_DEV_NULL:2,STDERR_TO_DEV_NULL:4},
        spawn_async: (...args) => {
            events.push(['spawn',args[1]])
            if (failNextSpawn && args[1][0] === failNextSpawn) { failNextSpawn = ''; return }
            running.add(args[1][0])
        },
        timeout_add: (_priority,_ms,fn) => { setImmediate(fn); },
    },
    Gio: {
        AppInfo: {
            get_all: () => appInfos.map(([id, name, show, fields]) => ({get_id: () => id, get_name: () => name, should_show: () => show, get_filename: () => '/usr/share/applications/' + id, get_string: key => fields[key] ?? null})),
            get_all_for_type: type => (appsForType[type] || []).map(([id,name]) => ({get_id: () => id, get_name: () => name})) },
        content_type_is_a: (mime, parent) => mime === parent || (mime === 'text/markdown' && parent === 'text/plain') || (parent === 'application/octet-stream' && !mime.startsWith('inode/')),
        FileCreateFlags:{NONE:0},
        FileQueryInfoFlags:{NONE:0,NOFOLLOW_SYMLINKS:1},
        FileType:{REGULAR:1,DIRECTORY:2,SYMBOLIC_LINK:3},
        IOErrorEnum:{EXISTS:2,NOT_FOUND:1},
        io_error_quark: () => 'g-io-error-quark',
        File:{new_for_path: path => ({
            query_exists: () => { const at = resolveLink(path); return at !== null && (files.has(at) || dirs.has(at)) },
            query_filesystem_info: attrs => {
                assert.equal(attrs,'filesystem::size,filesystem::used')
                const values = aboutAttributes.get(path)
                if (!values) throw new Error('No filesystem information')
                return {get_attribute_uint64: key => values[key]}
            },
            read: () => {
                if (!files.has(path)) throw new Error('Missing stream')
                const bytes = encoder.encode(files.get(path)); let at = 0
                return {seek: offset => {at = offset; aboutStreamReads.push(['seek',offset])},
                    read_bytes: count => {if (failAboutTail && count === 256*1024) throw new Error("Tail unreadable"); aboutStreamReads.push(['read',count]); const result = bytes.slice(at,at+count); at += result.length; return {get_data: () => result}},close: () => {}}
            },
            query_info: (attrs, flags) => {
                if (aboutAttributes.has(path)) return {get_attribute_uint64: key => aboutAttributes.get(path)[key]}
                if (attrs === 'standard::size' && files.has(path)) return {get_size: () => encoder.encode(files.get(path)).length}
                const nofollow = flags === 1
                if (nofollow && links.has(path)) return {get_is_symlink: () => true, get_file_type: () => 3}
                const at = resolveLink(path)
                if (at === null || !(files.has(at) || dirs.has(at))) throw gioError(1, 'No such file: '+path)
                return {get_is_symlink: () => links.has(path), get_file_type: () => files.has(at) ? 1 : 2, get_attribute_boolean: key => key === 'access::can-read' ? files.has(at) && !unreadableAvatars.has(path) : files.has(at) && execs.has(at)}
            },
            enumerate_children: () => {
                if (!dirs.has(path)) throw new Error('No such directory: '+path)
                const names = [...dirs.get(path)]
                return { next_file: () => names.length ? {get_name: (n => () => n)(names.shift())} : null, close: () => {} }
            },
            load_contents: () => {
                if (path === failingReadPath) throw new Error('Permission denied: '+path)
                const at = resolveLink(path)
                if (at === null || !files.has(at)) throw new Error('Missing fixture: '+path)
                const content = files.get(at)
                return [true, typeof content === 'string' ? encoder.encode(content) : content]
            },
            replace_contents: bytes => {
                events.push(['write',path])
                if (path === failingPath) throw new Error('disk full')
                files.set(resolveLink(path) ?? links.get(path),new TextDecoder('utf-8',{ignoreBOM:true}).decode(bytes))
                return [true,'etag']
            },
            create: () => {
                if (files.has(path) || dirs.has(path) || links.has(path) || raceOnce.delete(path)) throw gioError(2, 'File exists: '+path)
                if (!/\/\.[^/]*\.tmp$/.test(path)) events.push(['create',path])
                return {write_all: bytes => { files.set(path,new TextDecoder('utf-8',{ignoreBOM:true}).decode(bytes)); return [true,bytes.length] }, close: () => true}
            },
            delete: () => {
                if (!/\/\.[^/]*\.tmp$/.test(path)) events.push(['delete',path])
                links.delete(path)
                files.delete(path)
                return true
            },
            make_directory_with_parents: () => {
                events.push(['mkdir',path])
                dirs.set(path,[])
                return true
            },
        })},
    },
    GioUnix: {
        DesktopAppInfo: { new: id => supportedTypes[id] ? {get_supported_types: () => supportedTypes[id]} : null },
    },
    execAsync: async args => {
        events.push(args)
        if (args[0] === 'hyprctl' && args[1] === 'version') { if (aboutCommandsMissing) throw new Error('No compositor'); return JSON.stringify({tag:'v0.54.0'}) }
        if (args[0] === 'lspci') { if (aboutCommandsMissing) throw new Error('No lspci'); return '01:00.0 "VGA compatible controller" "NVIDIA Corporation" "GA104 [GeForce RTX 3070]"' }
        if (args[0] === 'localectl' && args[1] === 'list-locales') return 'C.UTF-8\nen_US.UTF-8\nit_IT.UTF-8\nde_DE.ISO-8859-1'
        if (args[0] === 'xdg-mime' && args[1] === 'query') return (mimeDefaults[args[3]] || '') + '\n'
        if (args[0] === 'xdg-mime' && args[1] === 'default') {
            if (args[3] === failMime) throw new Error('xdg-mime failed')
            mimeDefaults[args[3]] = args[2]
            files.set(base+'/mimeapps.list',(files.get(base+'/mimeapps.list') || '[Default Applications]\n') + `${args[3]}=${args[2]}\n`)
            return ''
        }
        if (args[0] === 'env' && args[2] === 'ln') {
            // link(2): never overwrites; the published file is a complete copy of the temporary one.
            const [, , , , from, to] = args
            if (files.has(to) || links.has(to) || raceOnce.delete(to)) throw new Error(`ln: failed to create hard link '${to}': File exists`)
            events.push(['create', to])
            files.set(to, files.get(from))
            return ''
        }
        if (args[0] === 'systemctl' && args[2] === 'show-environment') return showEnvironment
        if (args[0] === 'systemctl' && args[2] === 'list-units') return JSON.stringify([{unit:'app-nm\\x2dapplet@autostart.service',active:'active',sub:'running'}])
        if (args[0] === 'fc-list') return 'FiraCode Nerd Font,FiraCode Nerd Font Med\nAdwaita Sans\n'
        if (args[0] === 'secret-tool') { if (!keyringAccount) throw new Error('secret not found'); return keyringAccount }
        if (String(args[1]).endsWith('/scripts/calendar/cal.sh')) { if (calendarsListing === null) throw new Error('{"ok":false}'); return calendarsListing }
        if (String(args[1]).endsWith('/scripts/calendar/sync.sh') && failCalendarRenders > 0) { failCalendarRenders--; throw new Error('sync.sh --render failed') }
        if (args[0] === 'pkill') { running.delete(args[2]); return ''; }
        if (args[0] === 'pgrep') { if (!running.has(args[2])) throw new Error('not running'); return '123'; }
        if (args[1] === 'getoption') return JSON.stringify(hyprOptions[args[2]] ?? {int:1,set:true})
        if (args[1] === 'animations') return JSON.stringify([[{name:'windows',enabled:true,speed:6,bezier:'ease',style:'popin 80%'}],[]])
        if (args[1] === 'monitors') return JSON.stringify(monitorsFixture)
        if (args[1] === 'eval' && failEval) return 'error: bad monitor'
        if (args[1] === 'eval' && expireOnEval) guardArmed = false
        if (args[1] === 'reload' && failHyprReload) return 'error: reload failed'
        if (args[0] === 'systemd-run') {
            if (guardArmed) throw new Error('Unit settings-display-revert.timer was already loaded')
            guardArmed = true; return ''
        }
        if (args[0] === 'systemctl' && args.includes('is-active')) { if (!guardArmed) throw new Error('inactive'); return '' }
        if (args[0] === 'systemctl' && args.includes('stop')) {
            if (stopFails) throw new Error('Failed to connect to bus')
            // The timer fires between Keep's check and its stop.
            if (fireOnStop) { guardArmed = false; events.push(['hyprctl','reload','(guard)']); throw new Error('Unit settings-display-revert.timer not loaded.') }
            if (!guardArmed) throw new Error('Unit settings-display-revert.timer not loaded.'); guardArmed = false; return '' }
        if (args[1] === 'configerrors') return '[]'
        if (args[0] === 'swaync-client' && failReload) { failReload=false; throw new Error('reload failed') }
        if (args[0] === 'localectl') return {
            'list-x11-keymap-layouts': 'us\nit\nde\n',
            'list-x11-keymap-options': 'caps:escape\ngrp:alt_shift_toggle\n',
            'list-x11-keymap-variants': args[2] === 'us' ? 'intl\ncolemak\n' : 'nodeadkeys\n',
        }[args[1]]
        if (args[0] === 'gsettings' && args[1] === 'get') return gsettings[args[3]]
        if (args[0] === 'gsettings' && args[1] === 'set') {
            if (failingGsettingsSets > 0) { failingGsettingsSets--; throw new Error('gsettings set failed') }
            gsettings[args[3]] = args[4]; return ''
        }
        if (args[0] === 'powerprofilesctl') return args[1] === 'get' ? 'performance\n'
            : args[1] === 'list' ? '* performance:\n    CpuDriver:\tintel_pstate\n\n  balanced:\n    CpuDriver:\tintel_pstate\n\n  power-saver:\n    CpuDriver:\tintel_pstate\n' : ''
        if (args[0] === 'pactl' && args[1] === '-f') return JSON.stringify(args[3] === 'info' ? pulse.info : pulse[args[4]])
        if (args[0] === 'pactl') {
            if (args[1] === 'set-default-sink') pulse.info.default_sink_name = args[2]
            return ''
        }
        return 'ok'
    },
    // Credentials travel on stdin only: the mock records what the child would read.
    execInput: async (args, input) => { events.push(['stdin', args, input]); if (signInError) throw new Error(signInError); return '' },
    nm: nmMock,
    dbus: dbusMock,
}
registerHooks({resolve(specifier,context,next) {
    const names = {'gi://GLib':'GLib','gi://Gio':'Gio','gi://GioUnix':'GioUnix'}
    if (names[specifier]) return {url:'data:text/javascript,'+encodeURIComponent(`export default globalThis.settingsMocks.${names[specifier]}`),shortCircuit:true}
    if (specifier === './process.js') return {url:'data:text/javascript,export const execAsync = globalThis.settingsMocks.execAsync, execInput = (...a) => globalThis.settingsMocks.execInput(...a)',shortCircuit:true}
    if (specifier === './nm.js') return {url:'data:text/javascript,'+encodeURIComponent('const m = () => globalThis.settingsMocks.nm; export const nmSnapshot = (...a) => m().nmSnapshot(...a), setWifiEnabled = (...a) => m().setWifiEnabled(...a), requestScan = (...a) => m().requestScan(...a), activate = (...a) => m().activate(...a), addAndActivate = (...a) => m().addAndActivate(...a), deactivate = (...a) => m().deactivate(...a), removeConnections = (...a) => m().removeConnections(...a)'),shortCircuit:true}
    if (specifier === './dbus.js') return {url:'data:text/javascript,'+encodeURIComponent('const m = () => globalThis.settingsMocks.dbus; export const callSystem = (...a) => m().callSystem(...a), getProperty = (...a) => m().getProperty(...a); export const CANCELLED = "Authentication was cancelled; nothing changed."'),shortCircuit:true}
    return next(specifier,context)
}})
const originalCallSystem = dbusMock.callSystem
const originalGetProperty = dbusMock.getProperty
dbusMock.callSystem = async (...args) => {
    if (args[0] === 'org.freedesktop.Accounts') { events.push(['accounts-dbus']); throw new Error('AccountsService must not be contacted') }
    return originalCallSystem(...args)
}
dbusMock.getProperty = async (...args) => {
    if (args[0] === 'org.freedesktop.Accounts') { events.push(['accounts-dbus']); throw new Error('AccountsService must not be contacted') }
    return originalGetProperty(...args)
}
const {dispatch} = await import('../backend.js')
const displays = await import('../displays.mjs')
const {parseLocaleConf} = await import('../region.js')
const {authErrorMessage, interactiveErrorMessage, CANCELLED, NO_AGENT, TIMED_OUT} = await import('../authError.mjs')

assert.deepEqual(parseLocaleConf(`
# generated locale
export LANG="en_US.UTF-8"
LC_TIME='it_IT.UTF-8'
LC_NUMERIC="de_DE.UT\\F-8"
LC_MONETARY=fr_FR.UTF-8 # local convention
BROKEN="unterminated
`), {
    LANG: 'en_US.UTF-8',
    LC_TIME: 'it_IT.UTF-8',
    LC_NUMERIC: 'de_DE.UTF-8',
    LC_MONETARY: 'fr_FR.UTF-8',
})
assert.equal(authErrorMessage('GDBus.Error:org.freedesktop.PolicyKit1.Error.NotAuthorized: no'), CANCELLED)
assert.equal(authErrorMessage('GDBus.Error:org.freedesktop.PolicyKit1.Error.Cancelled: dismissed'), CANCELLED)
assert.equal(authErrorMessage('GDBus.Error:org.freedesktop.DBus.Error.AccessDenied: denied'), CANCELLED)
assert.equal(authErrorMessage('GDBus.Error:org.freedesktop.DBus.Error.InteractiveAuthorizationRequired: no agent'), NO_AGENT)
assert.equal(authErrorMessage('GDBus.Error:org.example.Error.AccessDenied: original'), null)
assert.equal(authErrorMessage('GDBus.Error:org.freedesktop.DBus.Error.AccessDeniedExtra: original'), null)
assert.equal(authErrorMessage('GDBus.Error:org.freedesktop.PolicyKit1.Error.Failed: original'), null)
assert.equal(interactiveErrorMessage('any message', true), TIMED_OUT)
console.log('ok: locale.conf syntax and interactive authentication errors are classified precisely')
let result = await dispatch({op:'read',ids:['appearance.blur','power.lock','power.nightlight-temp','notif.timeout','apps.browser'],monitors:true})
assert.equal(result.values['appearance.blur'].value,true)
assert.equal(result.values['power.nightlight-temp'].value,4000)
assert.equal(result.monitors[0].name,'DP-1')
assert.equal(events.some(e => e[0] === 'write' || e[0] === 'spawn'),false)
console.log('ok: settings and monitor reads have no writes or daemon starts')

result = await dispatch({op:'read',ids:['appearance.shadows','appearance.gaps-in']})
assert.equal(result.values['appearance.shadows'].value,false)
assert.equal(result.values['appearance.gaps-in'].value,4)
console.log('ok: keyword reads use the typed value field, never `set`')

events=[]
for (const request of [
    {op:'set',id:'not-real',value:1},
    {op:'set',id:'appearance.blur-size',value:100},
    {op:'set',id:'power.lock',value:80.5},
    {op:'set',id:'appearance.blur',value:'true'},
    {op:'set',id:'win.layout',value:'$(touch /tmp/should-not-exist)'},
    {op:'set',id:'apps.browser',value:'line\nbreak'},
    {op:'reset',id:'apps.browser'},
    {op:'action',id:'../../anything'},
    {op:'action',id:'monitors'},
]) await assert.rejects(dispatch(request))
assert.equal(events.length,0)
console.log('ok: invalid settings, types, ranges, actions and resets are rejected before side effects')

const text = 'browser with "quotes"; $(touch /tmp/never) `false`'
await dispatch({op:'set',id:'apps.browser',value:text})
assert.equal(files.get(base+'/options/browser'),text+'\n')
assert.equal(events.some(e=>e[0]==='bash'),false)
console.log('ok: option text remains data, never shell code')

events = []
await dispatch({op:'set',id:'region.clock',value:'12h'})
assert.equal(files.get(base+'/options/clock'), '12h\n')
assert.equal(events.filter(e => e[0] === 'bash' && String(e[1]).endsWith('/scripts/waybar/clock-format.sh')).length, 1)
await assert.rejects(dispatch({op:'set',id:'region.clock',value:'13h'}), /Unknown choice/)
console.log('ok: clock row renders the Waybar include')

events = []
await dispatch({op:'set',id:'bar.cpu',value:'high'})
assert.equal(files.get(base+'/options/bar-cpu'), 'high\n')
assert.equal(events.filter(e => e[0] === 'bash' && String(e[1]).endsWith('/scripts/waybar/bar-modes.sh')).length, 1)
const beforeInvalidBar = new Map(files)
const beforeInvalidBarEvents = events.length
await assert.rejects(dispatch({op:'set',id:'bar.cpu',value:'banana'}), /Unknown choice/)
assert.deepEqual(files, beforeInvalidBar)
assert.equal(events.length, beforeInvalidBarEvents)
events = []
await dispatch({op:'set',id:'bar.network',value:'offline'})
assert.equal(files.get(base+'/options/bar-network'), 'offline\n')
assert.equal(events.filter(e => e[0] === 'bash' && String(e[1]).endsWith('/scripts/waybar/bar-modes.sh')).length, 1)
await dispatch({op:'set',id:'bar.updates',value:'hidden'})
assert.equal(files.get(base+'/options/bar-updates'), 'hidden\n')
assert.ok(catalog.categories.some(c => c.id === 'bar'))
assert.deepEqual(catalog.rows.filter(r => r.category === 'bar').map(r => r.key).sort(),
    ['bar-agenda','bar-border','bar-cpu','bar-disk','bar-gpu','bar-memory','bar-network','bar-opacity','bar-output',
     'bar-position','bar-style','bar-updates','bar-workspaces','clock-seconds'])
files.set(base+'/options/bar-disk','banana\n')
result = await dispatch({op:'read',ids:['bar.disk','bar.updates']})
assert.equal(result.values['bar.disk'].value,'always')
assert.equal(result.values['bar.updates'].value,'hidden')
console.log('ok: bar rows render the Waybar include')

// By id: the panel's grouping decides the catalog order, and titles are presentation.
const layoutRows = ['bar.position','bar.style','bar.opacity','bar.border','bar.output','bar.clock-seconds','bar.workspaces']
    .map(id => catalog.rows.find(row => row.id === id))
assert.deepEqual(layoutRows.map(row => [row.id, row.source, row.kind]), [
    ['bar.position','option','select'],
    ['bar.style','option','select'],
    ['bar.opacity','option','slider'],
    ['bar.border','option','toggle'],
    ['bar.output','option','select'],
    ['bar.clock-seconds','option','toggle'],
    ['bar.workspaces','option','select'],
])
assert.deepEqual(layoutRows.slice(0,2).map(row => row.reload), [true,true])
const opacityRow = layoutRows[2]
assert.deepEqual([opacityRow.min,opacityRow.max,opacityRow.step,opacityRow.default], [0,100,5,50])
assert.equal(layoutRows[4].choices,'monitors')
for (const [id,key,values,script,reload] of [
    ['bar.position','bar-position',['bottom','top'],'bar-modes.sh',true],
    ['bar.style','bar-style',['docked','floating'],'bar-modes.sh',true],
    ['bar.opacity','bar-opacity',[55],'bar-modes.sh',false],
    ['bar.border','bar-border',[false,true],'bar-modes.sh',false],
    ['bar.output','bar-output',['DP-1',''],'bar-modes.sh',false],
    ['bar.clock-seconds','clock-seconds',[true,false],'clock-format.sh',false],
    ['bar.workspaces','bar-workspaces',['numbers','dots'],'bar-modes.sh',false],
]) for (const value of values) {
    events = []
    await dispatch({op:'set',id,value})
    const text = typeof value === 'boolean' ? (value ? 'enabled' : 'disabled') : String(value)
    assert.equal(files.get(`${base}/options/${key}`),text+'\n')
    assert.deepEqual(events.filter(e => e[0] === 'bash'), [['bash',`${base}/scripts/waybar/${script}`]])
    assert.equal(events.filter(e => e[0] === 'hyprctl' && e[1] === 'reload').length,reload ? 1 : 0)
}
files.set(base+'/options/bar-opacity','50\n')
result = await dispatch({op:'read',ids:['bar.opacity','bar.output']})
assert.equal(result.values['bar.opacity'].value,50)
assert.equal(result.values['bar.output'].value,'')
assert.deepEqual(result.values['bar.output'].choices,[
    {label:'All monitors',value:''},
    {label:'DP-1 — Ancor Communications Inc ROG PG279Q',value:'DP-1'},
])
assert.ok(events.some(e => e[0] === 'hyprctl' && e[1] === 'monitors' && e[2] === '-j'))
for (const value of ['broken','', 'Infinity']) {
    files.set(base+'/options/bar-opacity',value+'\n')
    result = await dispatch({op:'read',ids:['bar.opacity','test.option-slider']})
    assert.equal(result.values['bar.opacity'].value,50)
    assert.equal(result.values['test.option-slider'].value,10)
}
// A missing file disables the row, as for every option row: a save could not
// recreate it (saveAndApply reads the old file first).
files.delete(base+'/options/bar-opacity')
result = await dispatch({op:'read',ids:['bar.opacity']})
assert.ok(result.values['bar.opacity'].error)
files.set(base+'/options/bar-opacity','50\n')
files.set(base+'/options/bar-output','HDMI-A-1\n')
result = await dispatch({op:'read',ids:['bar.output']})
assert.equal(result.values['bar.output'].value,'HDMI-A-1')
assert.deepEqual(result.values['bar.output'].choices.at(-1),{label:'HDMI-A-1 (disconnected)',value:'HDMI-A-1'})
await dispatch({op:'set',id:'bar.output',value:'HDMI-A-1'})
files.set(base+'/options/bar-output','\n')
for (const [id,value] of [['bar.opacity',-5],['bar.opacity',105],['bar.opacity','55'],['bar.output','DP-UNKNOWN']]) {
    events = []
    const before = new Map(files)
    await assert.rejects(dispatch({op:'set',id,value}), /outside this setting's range|Unknown choice/)
    assert.deepEqual(files,before)
    assert.equal(events.some(e => ['write','bash'].includes(e[0]) || e[1] === 'reload'),false)
}
for (const [text, expected] of [['0x10\n', 50], ['500\n', 50], ['1e1\n', 50], ['35\n', 35]]) {
    files.set(base+'/options/bar-opacity', text)
    assert.equal((await dispatch({op:'read',ids:['bar.opacity']})).values['bar.opacity'].value, expected)
}
for (const [text, expected] of [['banana\n', true], ['\n', true], ['disabled\n', false], ['enabled\n', true]]) {
    files.set(base+'/options/bar-border', text)
    assert.equal((await dispatch({op:'read',ids:['bar.border']})).values['bar.border'].value, expected)
}
console.log('ok: bar layout rows persist typed values, enumerate monitors and validate before applying')

await dispatch({op:'set',id:'anim.windows',value:8})
assert.match(files.get('/fixture/.local/state/hypr/overrides.lua'),/speed = 8/)
assert.match(files.get('/fixture/.local/state/hypr/overrides.lua'),/bezier = "ease"/)
assert.match(files.get('/fixture/.local/state/hypr/overrides.lua'),/style = "popin 80%"/)
console.log('ok: animation speed edits preserve the live curve and style')

await dispatch({op:'set',id:'notif.timeout',value:8})
assert.deepEqual(JSON.parse(files.get(base+'/swaync/config.json')).unrelated,{keep:true})
const before = files.get(base+'/swaync/config.json')
failReload=true
await assert.rejects(dispatch({op:'set',id:'notif.timeout',value:10}),/Previous settings restored/)
assert.equal(files.get(base+'/swaync/config.json'),before)
console.log('ok: notification edits preserve unrelated configuration and roll back failed reloads')

failingPath=base+'/options/terminal'
await assert.rejects(dispatch({op:'set',id:'apps.terminal',value:'ghostty'}),/disk full/)
failingPath=''
await dispatch({op:'mainMonitor',value:'DP-1'})
assert.equal(files.get(base+'/options/mainmonitor'),'DP-1\n')
assert.equal(files.get(base+'/hypr/config/hardware/primary.conf'),'$monitor = DP-1\n')
failingPath=base+'/hypr/config/hardware/primary.conf'
await assert.rejects(dispatch({op:'mainMonitor',value:''}),/disk full/)
assert.equal(files.get(base+'/options/mainmonitor'),'DP-1\n')
console.log('ok: file failures propagate and partial main-monitor writes are restored')

const oldSunset = files.get(base+'/hypr/hyprsunset.conf')
failingPath=''
await dispatch({op:'set',id:'power.nightlight-start',value:1230})
assert.equal(files.get(base+'/hypr/hyprsunset.conf'),oldSunset.replace('20:00','20:30'))
await assert.rejects(dispatch({op:'set',id:'power.nightlight-start',value:420}),/different times/)
console.log('ok: night light edits preserve the rest of the file and reject conflicting schedule boundaries')
const oldIdle = files.get(base+'/hypr/hypridle.conf')
await dispatch({op:'set',id:'power.lock',value:330})
assert.equal(files.get(base+'/hypr/hypridle.conf'),oldIdle.replace('305','330'))
await dispatch({op:'set',id:'power.dpms',value:720})
assert.equal(files.get(base+'/hypr/hypridle.conf'),oldIdle.replace('305','330').replace('600','720'))
console.log('ok: idle timeout edits preserve custom content and Lua dispatcher arguments')

result = await dispatch({op:'read',ids:['power.profile','power.suspend']})
assert.equal(result.values['power.profile'].value,'performance')
assert.deepEqual(result.values['power.profile'].choices.map(c=>c.value),['performance','balanced','power-saver'])
assert.equal(result.values['power.suspend'].value,0)
await dispatch({op:'set',id:'power.profile',value:'balanced'})
assert.ok(events.some(e=>e[0]==='powerprofilesctl' && e[1]==='set' && e[2]==='balanced'))
const idleBefore = files.get(base+'/hypr/hypridle.conf')
const idleNoNewline = idleBefore.replace(/\n$/,'')
const suspendAt = seconds => `# Suspend after inactivity\nlistener {\n    timeout = ${seconds}\n    on-timeout = systemctl suspend\n}\n`

// The round trip (set N, retime, set 0) must restore the file byte-for-byte
// regardless of how many trailing newlines it had before the suspend block
// ever existed - a file ending in 0, 1 or 2+ newlines are three distinct cases.
for (const [label,original] of [['no trailing newline',idleNoNewline],['one trailing newline',idleBefore],['two trailing newlines',idleBefore+'\n']]) {
    files.set(base+'/hypr/hypridle.conf',original)

    events=[]
    await dispatch({op:'set',id:'power.suspend',value:1800})
    assert.ok(events.some(e=>e[0]==='pkill' && e[2]==='hypridle'),`add restarts hypridle (${label})`)
    assert.ok(events.some(e=>e[0]==='spawn' && e[1][0]==='hypridle'),`add spawns hypridle (${label})`)
    assert.equal(files.get(base+'/hypr/hypridle.conf'),original+'\n\n'+suspendAt(1800),`add is byte-exact (${label})`)

    events=[]
    await dispatch({op:'set',id:'power.suspend',value:3600})
    assert.ok(events.some(e=>e[0]==='pkill' && e[2]==='hypridle'),`retime restarts hypridle (${label})`)
    assert.ok(events.some(e=>e[0]==='spawn' && e[1][0]==='hypridle'),`retime spawns hypridle (${label})`)
    assert.equal(files.get(base+'/hypr/hypridle.conf'),original+'\n\n'+suspendAt(3600),`retime keeps everything else identical (${label})`)

    events=[]
    await dispatch({op:'set',id:'power.suspend',value:0})
    assert.ok(events.some(e=>e[0]==='pkill' && e[2]==='hypridle'),`remove restarts hypridle (${label})`)
    assert.ok(events.some(e=>e[0]==='spawn' && e[1][0]==='hypridle'),`remove spawns hypridle (${label})`)
    assert.equal(files.get(base+'/hypr/hypridle.conf'),original,`removal restores the file byte-for-byte (${label})`)
}
files.set(base+'/hypr/hypridle.conf',idleBefore)

files.set(base+'/hypr/hypridle.conf',idleBefore+'listener {\n timeout = 99\n on-timeout = systemctl suspend\n}\n')
await assert.rejects(dispatch({op:'set',id:'power.suspend',value:0}),/by hand/)
const customIdle = files.get(base+'/hypr/hypridle.conf')
await assert.rejects(dispatch({op:'set',id:'power.suspend',value:1800}),/by hand/)
assert.equal(files.get(base+'/hypr/hypridle.conf'),customIdle,'a custom suspend listener is never retimed')
files.set(base+'/hypr/hypridle.conf',idleBefore)
console.log('ok: power profile and suspend listener round-trip without touching custom content')

const idleForFailure = files.get(base+'/hypr/hypridle.conf')
failNextSpawn = 'hypridle'
await assert.rejects(dispatch({op:'set',id:'power.suspend',value:1800}),/Previous settings restored/)
assert.equal(files.get(base+'/hypr/hypridle.conf'),idleForFailure)
assert.equal(failNextSpawn,'')
console.log('ok: a suspend change that fails to restart hypridle restores hypridle.conf exactly')

result = await dispatch({op:'read',ids:['input.accel-profile']})
assert.equal(result.values['input.accel-profile'].value,'')
console.log('ok: an empty string keyword value maps through the [[EMPTY]] sentinel')

events=[]
await assert.rejects(dispatch({op:'set',id:'input.kb-layout',value:'zz'}),/Unknown keyboard layout zz/)
await assert.rejects(dispatch({op:'set',id:'input.kb-layout',value:'de'}),/de has no variant intl/)
await assert.rejects(dispatch({op:'set',id:'input.kb-options',value:'caps:nope'}),/Unknown keyboard option/)
await assert.rejects(dispatch({op:'set',id:'apps.browser',value:''}),/nonempty/)
assert.equal(events.some(e => e[1] === 'eval'),false)
await dispatch({op:'set',id:'input.kb-variant',value:''})
await dispatch({op:'set',id:'input.kb-options',value:'caps:escape,grp:alt_shift_toggle'})
await dispatch({op:'set',id:'input.kb-layout',value:'us,it'})
assert.match(files.get('/fixture/.local/state/hypr/overrides.lua'),/kb_variant = ""/)
assert.match(files.get('/fixture/.local/state/hypr/overrides.lua'),/kb_layout = "us,it"/)
console.log('ok: keyboard layout, variant and options are checked against XKB before applying')

await dispatch({op:'set',id:'input.kb-variant',value:'intl'})
events=[]
await assert.rejects(dispatch({op:'reset',id:'input.kb-layout'}),/Reset Layout Variant first/)
assert.equal(events.some(e => e[1] === 'reload'),false)
assert.match(files.get('/fixture/.local/state/hypr/overrides.lua'),/kb_layout = "us,it"/)
await dispatch({op:'reset',id:'input.kb-variant'})
await dispatch({op:'reset',id:'input.kb-layout'})
assert.doesNotMatch(files.get('/fixture/.local/state/hypr/overrides.lua'),/@override input:kb_layout /)
console.log('ok: resetting the keyboard layout while a variant override exists is rejected until the variant is reset first')

result = await dispatch({op:'read',ids:['appearance.gtk-theme','appearance.icon-theme']})
assert.deepEqual(result.values['appearance.gtk-theme'].choices.map(c=>c.value),['A$&B','Adwaita','HighContrast','HighContrastInverse','Kripton'])
assert.deepEqual(result.values['appearance.icon-theme'].choices.map(c=>c.value),['Papirus-Dark'])
assert.equal(result.values['appearance.gtk-theme'].value,'Kripton')
assert.equal(result.values['appearance.gtk-theme'].choices.some(c=>c.value==='Emacs'),false)
assert.equal(result.values['appearance.gtk-theme'].choices.some(c=>c.value==='Bad\nTheme'),false)
const systemThemes = dirs.get('/usr/share/themes')
dirs.set('/usr/share/themes',[])
result = await dispatch({op:'read',ids:['appearance.gtk-theme']})
assert.deepEqual(result.values['appearance.gtk-theme'].choices.map(c=>c.value),['Adwaita','HighContrast','HighContrastInverse'])
dirs.set('/usr/share/themes',systemThemes)
events=[]
await assert.rejects(dispatch({op:'set',id:'appearance.gtk-theme',value:'NoGtk'}),/Unknown choice/)
assert.equal(events.some(e=>e[0]==='gsettings'),false)
await dispatch({op:'set',id:'appearance.gtk-theme',value:'Adwaita'})
assert.equal(gsettings['gtk-theme'],"'Adwaita'")
assert.equal(files.get(base+'/gtk-3.0/settings.ini'),'[Settings]\ngtk-theme-name=Adwaita\ngtk-font-name=Sans 11\n')
assert.equal(files.get(base+'/gtk-4.0/settings.ini'),'[Settings]\ngtk-theme-name=Adwaita\n')
files.set(base+'/gtk-3.0/settings.ini','[Settings]')
files.set(base+'/gtk-4.0/settings.ini','[Settings]\r\ngtk-font-name=Sans 11\r\n')
await dispatch({op:'set',id:'appearance.gtk-theme',value:'A$&B'})
assert.equal(files.get(base+'/gtk-3.0/settings.ini'),'[Settings]\ngtk-theme-name=A$&B\n')
assert.equal(files.get(base+'/gtk-4.0/settings.ini'),'[Settings]\r\ngtk-theme-name=A$&B\r\ngtk-font-name=Sans 11\r\n')
await assert.rejects(dispatch({op:'set',id:'appearance.gtk-theme',value:'Bad\nTheme'}),/Unknown choice/)
events=[]
await assert.rejects(dispatch({op:'set',id:'test.gtk-raw',value:'Bad\nTheme'}),/multiline/)
assert.equal(events.some(e=>e[0]==='write' || e[0]==='gsettings'),false)

const gtk3BeforeFailure = files.get(base+'/gtk-3.0/settings.ini')
const gtk4BeforeFailure = files.get(base+'/gtk-4.0/settings.ini')
events=[]
failingGsettingsSets=1
await assert.rejects(dispatch({op:'set',id:'appearance.gtk-theme',value:'Adwaita'}),/gsettings set failed\. Previous settings restored\./)
assert.equal(files.get(base+'/gtk-3.0/settings.ini'),gtk3BeforeFailure)
assert.equal(files.get(base+'/gtk-4.0/settings.ini'),gtk4BeforeFailure)
assert.deepEqual(events.filter(e=>e[0]==='gsettings' && e[1]==='set').at(-1),['gsettings','set','org.gnome.desktop.interface','gtk-theme',"'A$&B'"])
failingGsettingsSets=2
await assert.rejects(dispatch({op:'set',id:'appearance.gtk-theme',value:'Adwaita'}),/gsettings set failed\. Restoring the previous gsettings value also failed: gsettings set failed/)
assert.equal(files.get(base+'/gtk-3.0/settings.ini'),gtk3BeforeFailure)
assert.equal(files.get(base+'/gtk-4.0/settings.ini'),gtk4BeforeFailure)

events=[]
await dispatch({op:'set',id:'appearance.color-scheme',value:'prefer-dark'})
assert.match(files.get(base+'/gtk-3.0/settings.ini'),/^gtk-application-prefer-dark-theme=true$/m)
assert.match(files.get(base+'/gtk-4.0/settings.ini'),/^gtk-application-prefer-dark-theme=true$/m)
assert.deepEqual(events.find(e=>e[0]==='gsettings' && e[1]==='set'),['gsettings','set','org.gnome.desktop.interface','color-scheme',"'prefer-dark'"])
await dispatch({op:'set',id:'appearance.color-scheme',value:'prefer-light'})
assert.match(files.get(base+'/gtk-3.0/settings.ini'),/^gtk-application-prefer-dark-theme=false$/m)
console.log('ok: GTK appearance filters themes, preserves literal INI values and line endings, and rolls back failures')

result = await dispatch({op:'read',ids:['appearance.kvantum']})
assert.equal(result.values['appearance.kvantum'].value,'Carl')
assert.deepEqual(result.values['appearance.kvantum'].choices.map(c=>c.value),['Carl','KvArc'])
await dispatch({op:'set',id:'appearance.kvantum',value:'KvArc'})
assert.equal(files.get(base+'/Kvantum/kvantum.kvconfig'),'[General]\ntheme=KvArc\n')
files.set(base+'/Kvantum/kvantum.kvconfig','[Other]\ntheme=Wrong\n[General]\ntheme=Carl\n')
result = await dispatch({op:'read',ids:['appearance.kvantum']})
assert.equal(result.values['appearance.kvantum'].value,'Carl')
await dispatch({op:'set',id:'appearance.kvantum',value:'KvArc'})
assert.equal(files.get(base+'/Kvantum/kvantum.kvconfig'),'[Other]\ntheme=Wrong\n[General]\ntheme=KvArc\n')
files.set(base+'/Kvantum/kvantum.kvconfig','[General]\r\nkeep=true\r\n')
await dispatch({op:'set',id:'appearance.kvantum',value:'Carl'})
assert.equal(files.get(base+'/Kvantum/kvantum.kvconfig'),'[General]\r\ntheme=Carl\r\nkeep=true\r\n')
files.delete(base+'/Kvantum/kvantum.kvconfig')
await dispatch({op:'set',id:'appearance.kvantum',value:'Carl'})
assert.equal(files.get(base+'/Kvantum/kvantum.kvconfig'),'[General]\ntheme=Carl\n')
files.set(base+'/Kvantum/kvantum.kvconfig','[Other]\ntheme=Carl\n')
await assert.rejects(dispatch({op:'set',id:'appearance.kvantum',value:'KvArc'}),/has no \[General\] section/)
assert.equal(files.get(base+'/Kvantum/kvantum.kvconfig'),'[Other]\ntheme=Carl\n')
files.delete(base+'/Kvantum/kvantum.kvconfig')
dirs.delete(base+'/Kvantum')
events=[]
await dispatch({op:'set',id:'appearance.kvantum',value:'KvArc'})
assert.equal(dirs.has(base+'/Kvantum'),true)
assert.equal(files.get(base+'/Kvantum/kvantum.kvconfig'),'[General]\ntheme=KvArc\n')
assert.deepEqual(events.filter(e=>e[0]==='mkdir'),[['mkdir',base+'/Kvantum']])
console.log('ok: Kvantum theme is chosen from installed themes')

events=[]
await assert.rejects(dispatch({op:'set',id:'appearance.font',value:'No Such Font'}),/No installed font/)
assert.equal(events.some(e=>e[0]==='bash'),false)
await dispatch({op:'set',id:'appearance.font',value:'FiraCode Nerd Font Med'})
await dispatch({op:'set',id:'appearance.cursor-theme',value:'Bibata-Modern-Classic'})
assert.match(files.get(base+'/gtk-3.0/settings.ini'),/^gtk-cursor-theme-name=Bibata-Modern-Classic$/m)
assert.match(files.get(base+'/gtk-4.0/settings.ini'),/^gtk-cursor-theme-size=24$/m)
console.log('ok: fonts must be installed and the cursor theme reaches settings.ini')

events=[]
await assert.rejects(dispatch({op:'set',id:'apps.filemanager',value:'missing-app --flag'}),/missing-app is not installed/)
assert.equal(events.length,0)
await dispatch({op:'set',id:'apps.filemanager',value:'nautilus'})
assert.equal(files.get(base+'/options/filemanager'),'nautilus\n')
assert.ok(events.some(e=>e[1]==='reload'))
assert.equal(events.filter(e => e[0] === 'bash' && String(e[1]).endsWith('/scripts/settings/file-manager.sh')).length, 1)
events=[]
await dispatch({op:'set',id:'apps.terminal',value:'alacritty'})
assert.equal(files.get(base+'/options/terminal'),'alacritty\n')
assert.ok(events.some(e=>e[1]==='reload'))
assert.equal(events.filter(e => e[0] === 'bash' && String(e[1]).endsWith('/scripts/settings/terminal.sh')).length, 1)
assert.equal(events.filter(e => e[0] === 'bash' && String(e[1]).endsWith('/scripts/settings/file-manager.sh')).length, 0)
console.log('ok: app rows must name an installed command and reload Hyprland; the file manager also claims D-Bus, the terminal xdg-terminal-exec')

events=[]
result = await dispatch({op:'read',ids:['mime.folders','mime.images']})
assert.equal(result.values['mime.folders'].value,'kitty-open.desktop')
assert.deepEqual(result.values['mime.folders'].choices.map(c=>c.value),['thunar.desktop','org.gnome.Nautilus.desktop','kitty-open.desktop'])
assert.deepEqual(events.filter(e=>e[0]==='xdg-mime' && e[1]==='query').map(e=>e[3]).sort(),['image/png','inode/directory'])
await assert.rejects(dispatch({op:'set',id:'mime.folders',value:'evil.desktop'}),/Unknown choice/)
await dispatch({op:'set',id:'mime.folders',value:'thunar.desktop'})
assert.equal(mimeDefaults['inode/directory'],'thunar.desktop')
for (const mime of catalog.rows.find(row=>row.id==='mime.images').mimes) mimeDefaults[mime]='old.desktop'
events=[]
await dispatch({op:'set',id:'mime.images',value:'mpv.desktop'})
assert.deepEqual(events.filter(e=>e[0]==='xdg-mime' && e[1]==='default').map(e=>e[3]),['image/png','image/jpeg'])
assert.equal(mimeDefaults['image/gif'],'old.desktop')
events=[]
await dispatch({op:'set',id:'mime.text',value:'nvim.desktop'})
assert.deepEqual(events.filter(e=>e[0]==='xdg-mime' && e[1]==='default').map(e=>e[3]),['text/plain','text/markdown'])
events=[]
await dispatch({op:'set',id:'mime.images',value:'image-viewer.desktop'})
assert.deepEqual(events.filter(e=>e[0]==='xdg-mime' && e[1]==='default').map(e=>e[3]),['image/png'])
events=[]
await dispatch({op:'set',id:'mime.images',value:'hexed.desktop'})
assert.deepEqual(events.filter(e=>e[0]==='xdg-mime' && e[1]==='default').map(e=>e[3]),['image/png'])
const exactMimeapps = '[Default Applications]\r\nimage/png=old.desktop\r\n# image/jpeg deliberately has no explicit default\r\n'
files.set(base+'/mimeapps.list',exactMimeapps)
mimeDefaults['image/png']='old.desktop'; mimeDefaults['image/jpeg']='inferred.desktop'
failMime='image/jpeg'
await assert.rejects(dispatch({op:'set',id:'mime.images',value:'mpv.desktop'}),/xdg-mime failed/)
assert.equal(files.get(base+'/mimeapps.list'),exactMimeapps)
failingPath=base+'/mimeapps.list'
await assert.rejects(dispatch({op:'set',id:'mime.images',value:'mpv.desktop'}),/xdg-mime failed\. Restoring mimeapps\.list also failed: disk full/)
failingPath=''
files.delete(base+'/mimeapps.list')
await assert.rejects(dispatch({op:'set',id:'mime.images',value:'mpv.desktop'}),/xdg-mime failed/)
assert.equal(files.has(base+'/mimeapps.list'),false)
failMime=''
mimeDefaults['image/png']='legacy.desktop'
events=[]
await dispatch({op:'set',id:'mime.images',value:'legacy.desktop'})
assert.deepEqual(events.filter(e=>e[0]==='xdg-mime' && e[1]==='default').map(e=>e[3]),['image/png'])
console.log('ok: file types query once, update declared MIME subclasses only, and restore mimeapps.list exactly')

events=[]
result = await dispatch({op:'read',ids:catalog.rows.filter(r=>r.source==='pulse').map(r=>r.id)})
assert.equal(events.filter(e=>e[0]==='pactl').length,4)
const sound = id => result.values['sound.'+id]
assert.equal(sound('output').value,'alsa_output.analog')
assert.deepEqual(sound('output').choices.map(c=>c.value),['alsa_output.analog','alsa_output.hdmi'])
assert.deepEqual(sound('output-port').choices.map(c=>c.label),['Headphones'])
assert.deepEqual(sound('output-profile').choices.map(c=>c.value),['output:analog-stereo+input:analog-stereo','output:iec958-stereo'])
assert.deepEqual(sound('input').choices.map(c=>c.value),['alsa_input.analog'])
assert.deepEqual(sound('input-port').choices.map(c=>c.value),['analog-input-front-mic'])
assert.equal(sound('mic-level').value,62)
events=[]
await assert.rejects(dispatch({op:'set',id:'sound.output-port',value:'analog-output-lineout'}),/Unknown choice/)
await assert.rejects(dispatch({op:'set',id:'sound.output-profile',value:'off'}),/Unknown choice/)
await assert.rejects(dispatch({op:'set',id:'sound.output-profile',value:'input:analog-stereo'}),/Unknown choice/)
await assert.rejects(dispatch({op:'set',id:'sound.input',value:'alsa_output.analog.monitor'}),/Unknown choice/)
await assert.rejects(dispatch({op:'set',id:'sound.mic-level',value:151}),/outside/)
await assert.rejects(dispatch({op:'reset',id:'sound.output'}),/no reset/)
assert.equal(events.some(e=>e[0]==='pactl' && e[1].startsWith('set-')),false)
await dispatch({op:'set',id:'sound.output-port',value:'analog-output-headphones'})
await dispatch({op:'set',id:'sound.input',value:'alsa_input.analog'})
await dispatch({op:'set',id:'sound.input-port',value:'analog-input-front-mic'})
await dispatch({op:'set',id:'sound.output-profile',value:'output:iec958-stereo'})
await dispatch({op:'set',id:'sound.mic-level',value:40})
await dispatch({op:'set',id:'sound.output',value:'alsa_output.hdmi'})
assert.deepEqual(events.filter(e=>e[0]==='pactl' && e[1].startsWith('set-')).map(e=>e.slice(1)),[
    ['set-sink-port','alsa_output.analog','analog-output-headphones'],
    ['set-default-source','alsa_input.analog'],
    ['set-source-port','alsa_input.analog','analog-input-front-mic'],
    ['set-card-profile','alsa_card.analog','output:iec958-stereo'],
    ['set-source-volume','alsa_input.analog','40%'],
    ['set-default-sink','alsa_output.hdmi'],
])
result = await dispatch({op:'read',ids:['sound.output-port','sound.output-profile']})
assert.equal(result.values['sound.output-port'].value,'hdmi-output-0')
assert.equal(result.values['sound.output-profile'].value,'output:hdmi-stereo')
pulse.info.default_sink_name = 'alsa_output.analog'
const savedSource = pulse.info.default_source_name
pulse.info.default_source_name = ''
result = await dispatch({op:'read',ids:['sound.input','sound.input-port','sound.mic-level','sound.output']})
// The device selector stays usable with no valid default, so the panel can recover the state.
assert.equal(result.values['sound.input'].value,'')
assert.deepEqual(result.values['sound.input'].choices.map(c=>c.value),['alsa_input.analog'])
assert.match(result.values['sound.input-port'].error,/No input device/)
assert.match(result.values['sound.mic-level'].error,/No input device/)
assert.equal(result.values['sound.output'].value,'alsa_output.analog')
pulse.info.default_source_name = 'alsa_output.analog.monitor'
result = await dispatch({op:'read',ids:['sound.input']})
assert.equal(result.values['sound.input'].value,'')
pulse.info.default_source_name = savedSource
pulse.info.default_sink_name = 'alsa_output.gone'
result = await dispatch({op:'read',ids:['sound.output','sound.output-port','sound.output-profile']})
assert.equal(result.values['sound.output'].value,'')
assert.deepEqual(result.values['sound.output'].choices.map(c=>c.value),['alsa_output.analog','alsa_output.hdmi'])
assert.match(result.values['sound.output-port'].error,/No output device/)
assert.match(result.values['sound.output-profile'].error,/No output device/)
pulse.info.default_sink_name = 'alsa_output.analog'
const savedVolume = pulse.sources[1].volume
pulse.sources[1].volume = {}
result = await dispatch({op:'read',ids:['sound.mic-level']})
assert.match(result.values['sound.mic-level'].error,/no volume/)
pulse.sources[1].volume = savedVolume
console.log('ok: sound rows share four pactl reads, offer only usable choices and follow the default device')

const statePath = '/fixture/.local/state/hypr/monitors.lua'
const pendingPath = '/run/user/1000/settings-panel/display-pending.json'
events=[]
result = await dispatch({op:'read',ids:[],monitors:true})
assert.equal(result.monitors[0].saved,null)
assert.equal(result.monitors[0].handEdited,false)
assert.equal(result.monitors[0].choices.modes[0].value,'highres@highrr')
assert.equal(result.displayPending,null)
assert.ok(events.some(e=>e[0]==='hyprctl' && e[1]==='monitors' && e[2]==='all'))
events=[]
for (const [request, message] of [
    [{op:'displayApply',output:'DP-9',mode:'highres@highrr',position:'auto',scale:1,transform:0},/no longer connected/],
    [{op:'displayApply',output:'DP-1',mode:'9999x9999@1.00',position:'auto',scale:1,transform:0},/Unknown mode/],
    [{op:'displayApply',output:'DP-1',mode:'2560x1440@120.00',position:'0x0',scale:1,transform:0},/Unknown position/],
    [{op:'displayApply',output:'DP-1',mode:'2560x1440@120.00',position:'auto',scale:1,transform:9},/Unknown rotation/],
    [{op:'displayApply',output:'DP-1',mode:'2560x1440@120.00',position:'auto',scale:1.5,transform:0},/does not divide/],
    [{op:'displayApply',output:'DP-1',disabled:true},/must stay on/],
]) await assert.rejects(dispatch(request),message)
assert.equal(events.some(e=>e[0]==='systemd-run' || e[1]==='eval' || e[0]==='write'),false)
console.log('ok: display changes are validated before any guard, eval or write')

const apply = {op:'displayApply',output:'DP-1',mode:'2560x1440@120.00',position:'auto-left',scale:1.25,transform:0}
const line = 'hl.monitor({ output = "DP-1", mode = "2560x1440@120.00", position = "auto-left", scale = 1.25, transform = 0 })'
events=[]
const applied = await dispatch(apply)
const guard = events.find(e=>e[0]==='systemd-run')
for (const flag of ['--user','--collect','--unit=settings-display-revert','--on-active=20','--setenv=HYPRLAND_INSTANCE_SIGNATURE=sig']) assert.ok(guard.includes(flag),flag)
assert.deepEqual(guard.slice(-2),['hyprctl','reload'])
assert.ok(events.indexOf(guard) < events.findIndex(e=>e[1]==='eval'))
assert.deepEqual(events.find(e=>e[1]==='eval'),['hyprctl','eval',line])
assert.equal(applied.pending.output,'DP-1')
assert.equal(files.has(statePath),false)
await assert.rejects(dispatch(apply),/waiting for Keep or Revert/)
result = await dispatch({op:'read',ids:[],monitors:true})
assert.equal(result.displayPending.output,'DP-1')
assert.deepEqual(await dispatch({op:'displayKeep'}),{pending:null})
assert.equal(files.get(statePath),displays.STATE_HEADER+line+'\n')
assert.equal(files.has(pendingPath),false)
assert.equal(guardArmed,false)
result = await dispatch({op:'read',ids:[],monitors:true})
assert.deepEqual(result.monitors[0].saved,{mode:'2560x1440@120.00',position:'auto-left',scale:1.25,transform:0})
console.log('ok: Apply arms the guard before eval; Keep writes exactly the evaluated line')

await dispatch({op:'displayApply',output:'DP-1',automatic:true})
assert.deepEqual(events.filter(e=>e[1]==='eval').at(-1),['hyprctl','eval','hl.monitor({ output = "DP-1", mode = "highres@highrr", position = "auto", scale = 1, transform = 0 })'])
await dispatch({op:'displayKeep'})
assert.equal(files.get(statePath),displays.STATE_HEADER)
events=[]
await dispatch(apply)
await dispatch({op:'displayRevert'})
assert.ok(events.some(e=>e[1]==='reload'))
assert.equal(files.get(statePath),displays.STATE_HEADER)
assert.equal(files.has(pendingPath),false)
assert.equal(guardArmed,false)
console.log('ok: Automatic removes the line on Keep; Revert reloads and writes nothing')

await dispatch(apply)
guardArmed=false
await assert.rejects(dispatch({op:'displayKeep'}),/already reverted/)
assert.equal(files.get(statePath),displays.STATE_HEADER)
assert.equal(files.has(pendingPath),false)
await dispatch(apply); guardArmed=false
await dispatch(apply)
assert.equal(guardArmed,true)
await dispatch({op:'displayRevert'})
failEval=true
await assert.rejects(dispatch(apply),/error: bad monitor/)
failEval=false
assert.equal(guardArmed,false)
assert.equal(files.has(pendingPath),false)
console.log('ok: a fired guard wins over Keep, stale pending files expire, failed evals disarm')

monitorsFixture.push({name:'HDMI-A-1',disabled:false,width:1920,height:1080,availableModes:['1920x1080@60.00Hz']})
await dispatch({op:'displayApply',output:'HDMI-A-1',disabled:true})
assert.deepEqual(events.filter(e=>e[1]==='eval').at(-1),['hyprctl','eval','hl.monitor({ output = "HDMI-A-1", disabled = true })'])
await dispatch({op:'displayRevert'})
monitorsFixture.pop()
files.set(statePath,displays.STATE_HEADER+'hl.monitor({ output = "DP-1", mode = "preferred", position = "0x0", scale = 1, bitdepth = 10 })\n')
await assert.rejects(dispatch(apply),/edited by hand/)
result = await dispatch({op:'read',ids:[],monitors:true})
assert.equal(result.monitors[0].handEdited,true)
files.delete(statePath)
files.set(base+'/options/terminal','ghostty\n'); files.set(base+'/options/editor','nvim\n')
events=[]
await dispatch({op:'action',id:'displays-file'})
assert.equal(files.get(statePath),displays.STATE_HEADER)
assert.deepEqual(events.find(e=>e[0]==='spawn')[1],['ghostty','-e','nvim',statePath])
console.log('ok: a second display can be disabled, hand-edited outputs are refused, Edit file opens the state file')
// Review round: the guard is disarmed only once the display is known safe.
const stops = () => events.filter(e=>e[0]==='systemctl' && e.includes('stop'))
events=[]
await dispatch(apply)
await dispatch({op:'displayRevert'})
assert.ok(events.findIndex(e=>e[1]==='reload') < events.indexOf(stops()[0]),'Revert reloads while the guard is armed')
await dispatch(apply)
failHyprReload=true
await assert.rejects(dispatch({op:'displayRevert'}),/reload failed/)
failHyprReload=false
assert.equal(guardArmed,true)
assert.equal(files.has(pendingPath),true)
await dispatch({op:'displayRevert'})
await dispatch(apply)
stopFails=true
await assert.rejects(dispatch({op:'displayRevert'}),/Failed to connect/)
stopFails=false
assert.equal(files.has(pendingPath),true)
await dispatch({op:'displayRevert'})
assert.equal(guardArmed,false)
console.log('ok: Revert reloads before disarming and surfaces a guard it could not stop')

files.set(statePath,displays.STATE_HEADER)
events=[]
await dispatch(apply)
await dispatch({op:'displayKeep'})
assert.ok(events.findIndex(e=>e[0]==='write' && e[1]===statePath) < events.indexOf(stops()[0]),'Keep writes before disarming')
await dispatch({op:'displayApply',output:'DP-1',automatic:true}); await dispatch({op:'displayKeep'})
await dispatch(apply)
failingPath=statePath
await assert.rejects(dispatch({op:'displayKeep'}),/disk full\. The display will revert/)
failingPath=''
assert.equal(guardArmed,true)
await dispatch({op:'displayRevert'})
await dispatch(apply)
fireOnStop=true; events=[]
await dispatch({op:'displayKeep'})
fireOnStop=false
assert.equal(files.get(statePath),displays.STATE_HEADER+line+'\n')
assert.equal(events.filter(e=>e[1]==='reload' && e[2]!=='(guard)').length,1,'a guard that fired mid-Keep is followed by a reload of the kept file')
await dispatch({op:'displayApply',output:'DP-1',automatic:true}); await dispatch({op:'displayKeep'})
console.log('ok: Keep writes while the guard is armed and re-syncs if the guard fired meanwhile')

delete mockEnv.HYPRLAND_INSTANCE_SIGNATURE
events=[]
await dispatch(apply)
assert.equal(events.find(e=>e[0]==='systemd-run').some(a=>String(a).startsWith('--setenv')),false)
mockEnv.HYPRLAND_INSTANCE_SIGNATURE='sig'
await dispatch({op:'displayRevert'})
await assert.rejects(dispatch({op:'displayApply',output:'DP-1',automatic:true,disabled:true}),/not both/)
assert.equal(guardArmed,false)
console.log('ok: the guard inherits the session signature when none is set; contradictory requests are refused')
// Second review round: only an evaluated, still-guarded change can be kept.
events=[]
await dispatch(apply)
assert.ok(events.findIndex(e=>e[1]==='eval') < events.findIndex(e=>e[0]==='write' && e[1]===pendingPath),'the pending record follows a successful eval')
await dispatch({op:'displayRevert'})
failEval=true
await assert.rejects(dispatch(apply),/bad monitor/)
failEval=false
assert.equal(files.has(pendingPath),false)
expireOnEval=true
await assert.rejects(dispatch(apply),/took too long/)
expireOnEval=false
assert.equal(files.has(pendingPath),false)
assert.ok(events.filter(e=>e[1]==='reload').length > 0)
events=[]
await dispatch(apply)
await dispatch({op:'displayKeep'})
assert.equal(events.filter(e=>e[1]==='reload').length,1,'Keep always ends with a reload of the kept file')
await dispatch({op:'displayApply',output:'DP-1',automatic:true}); await dispatch({op:'displayKeep'})
files.set(pendingPath,JSON.stringify({output:'DP-1',line:'stale',remove:false,deadline:0}))
await assert.rejects(dispatch({op:'displayApply',output:'DP-1',automatic:true,disabled:true}),/not both/)
assert.equal(files.has(pendingPath),true,'a contradictory request changes nothing, not even stale state')
files.delete(pendingPath)
failingPath=pendingPath
events=[]
await assert.rejects(dispatch(apply),/disk full/)
failingPath=''
assert.ok(events.some(e=>e[1]==='reload'),'a failed pending write reverts the evaluated change')
assert.equal(files.has(pendingPath),false)
assert.equal(guardArmed,false)
console.log('ok: pending follows eval, an expired guard reverts, Keep reloads, contradictions touch nothing')
await dispatch(apply)
for (const request of [{op:'action',id:'reload'},{op:'reset',id:'appearance.shadows'},{op:'reset',id:'anim.windows'},{op:'set',id:'appearance.blur',value:false},{op:'mainMonitor',value:'DP-1'},{op:'action',id:'displays-file'},{op:'wifiConnect',ssid:'Cafe'},{op:'networkScan'}])
    await assert.rejects(dispatch(request),/Keep or Revert/,JSON.stringify(request))
result = await dispatch({op:'read',ids:['appearance.blur'],monitors:true})
assert.equal(result.displayPending.output,'DP-1')
await dispatch({op:'displayRevert'})
await dispatch({op:'action',id:'reload'})
console.log('ok: nothing reloads Hyprland under a display change awaiting Keep or Revert')
monitorsFixture.push({name:'HDMI-A-1',disabled:false,width:1920,height:1080,availableModes:['1920x1080@60.00Hz']})
files.set(base+'/options/mainmonitor','HDMI-A-1\n')
await assert.rejects(dispatch({op:'displayApply',output:'HDMI-A-1',disabled:true}),/main display/)
assert.equal(guardArmed,false)
files.set(base+'/options/mainmonitor','\n')
monitorsFixture.pop()
await dispatch({op:'mainMonitor',value:''})
assert.equal(files.get(base+'/hypr/config/hardware/primary.conf'),'$monitor =\n')
console.log('ok: the main display cannot be turned off, and no main display writes no trailing space')

nmCalls = []; events = []
result = await dispatch({op:'read',ids:['network.wifi'],network:true})
assert.equal(result.values['network.wifi'].value, true)
assert.deepEqual(result.network.wifi.networks.map(n => [n.ssid, n.known]), [['Dimensione-E92F', true], ['Cafe', false]])
assert.deepEqual(result.network.vpn.map(v => v.name), ['ProtonVPN IT#113'])
assert.equal(nmCalls.length, 0)
assert.equal(events.some(e => e[0] === 'write' || e[0] === 'spawn'), false)
console.log('ok: network read shapes the page and has no side effects')

nmState.running = false
result = await dispatch({op:'read',ids:['network.wifi'],network:true})
assert.match(result.values['network.wifi'].error, /not running/)
assert.deepEqual(result.network, {running:false})
nmState.running = true
console.log('ok: network — NetworkManager down is a row error, not a failed read')

await dispatch({op:'set',id:'network.wifi',value:false})
assert.deepEqual(nmCalls.at(-1), ['wifi', false])
await dispatch({op:'set',id:'network.wifi',value:true})
await dispatch({op:'networkScan'})
assert.deepEqual(nmCalls.at(-1), ['scan'])
console.log('ok: network radio switch and scan go through the adapter')

nmCalls = []
await dispatch({op:'wifiConnect',ssid:'Dimensione-E92F'})
assert.deepEqual(nmCalls, [['activate','u-old']])
nmCalls = []
await dispatch({op:'wifiConnect',ssid:'Dimensione-E92F',psk:'new password'})
assert.deepEqual(nmCalls, [['add','Dimensione-E92F','new password','wpa-psk'],['remove','u-old']])
nmCalls = []; nmFailAdd = 'Wrong password'
await assert.rejects(dispatch({op:'wifiConnect',ssid:'Dimensione-E92F',psk:'bad password'}), /Wrong password/)
assert.deepEqual(nmCalls, [['add','Dimensione-E92F','bad password','wpa-psk']])
nmFailAdd = ''; nmCalls = []
await dispatch({op:'wifiConnect',ssid:'Cafe'})
assert.deepEqual(nmCalls, [['add','Cafe',null,null]])
await assert.rejects(dispatch({op:'wifiConnect',ssid:'Cafe',psk:'short'}), /does not use a password/)
console.log('ok: network connect activates saved, adds new, replaces old only after success')

nmCalls = []
await dispatch({op:'wifiForget',ssid:'Dimensione-E92F'})
assert.deepEqual(nmCalls, [['remove','u-old']])
console.log('ok: network forget removes the single saved profile')

nmState.connections.push({uuid:'u-forget2', id:'Dimensione-E92F', type:'802-11-wireless', ssid:'Dimensione-E92F', state:null, iface:null})
nmCalls = []; nmFailRemove = new Set(['u-forget2'])
await assert.rejects(dispatch({op:'wifiForget', ssid:'Dimensione-E92F'}), /Some saved profiles for this network could not be removed: Cannot remove u-forget2/)
assert.deepEqual(nmCalls.map(c => c[1]), ['u-old', 'u-forget2'], 'every saved profile is attempted even though one fails')
nmFailRemove = new Set()
nmCalls = []; nmMissingRemove = new Set(['u-old'])
await dispatch({op:'wifiForget', ssid:'Dimensione-E92F'})
assert.deepEqual(nmCalls.map(c => c[1]), ['u-old', 'u-forget2'], 'an already-missing profile counts as removed, not a failure')
nmMissingRemove = new Set()
nmState.connections = nmState.connections.filter(c => c.uuid !== 'u-forget2')
console.log('ok: wifiForget removes every saved profile individually, tolerating an already-missing one, surfacing the first real failure')

await assert.rejects(dispatch({op:'vpn',uuid:'u-proton',active:false}), /Proton VPN app/)
await assert.rejects(dispatch({op:'vpn',uuid:'u-kill',active:false}), /not a VPN/)
events = []
await dispatch({op:'action',id:'protonApp'})
await dispatch({op:'action',id:'networkEditor'})
assert.deepEqual(events.filter(e => e[0] === 'spawn').map(e => e[1][0]), ['protonvpn-app','nm-connection-editor'])
console.log('ok: network forget, VPN refusal in app mode, and the two launch actions')

nmState.running = false
for (const request of [{op:'networkScan'},{op:'wifiConnect',ssid:'Cafe'},{op:'wifiForget',ssid:'Dimensione-E92F'},{op:'vpn',uuid:'u-work',active:true},{op:'set',id:'network.wifi',value:false}])
    await assert.rejects(dispatch(request), /NetworkManager is not running/, JSON.stringify(request))
nmState.running = true
console.log('ok: network write ops fail loudly when NetworkManager is not running')

nmState.connections.push({uuid:'u-old2', id:'Dimensione-E92F', type:'802-11-wireless', ssid:'Dimensione-E92F', state:null, iface:null})
nmCalls = []; nmFailRemove = new Set(['u-old', 'u-old2'])
await assert.rejects(dispatch({op:'wifiConnect', ssid:'Dimensione-E92F', psk:'new password'}), /old saved profile.*could not be removed/)
assert.deepEqual(nmCalls.filter(c => c[0] === 'add'), [['add','Dimensione-E92F','new password','wpa-psk']])
assert.deepEqual(nmCalls.filter(c => c[0] === 'remove').map(c => c[1]), ['u-old','u-old2'])
nmFailRemove = new Set(['u-old2'])
nmCalls = []
await assert.rejects(dispatch({op:'wifiConnect', ssid:'Dimensione-E92F', psk:'new password'}), /old saved profile.*could not be removed/)
assert.deepEqual(nmCalls.filter(c => c[0] === 'remove').map(c => c[1]), ['u-old','u-old2'], 'a later failure does not stop earlier removals from being attempted')
nmFailRemove = new Set()
nmState.connections = nmState.connections.filter(c => c.uuid !== 'u-old2')
console.log('ok: wifiConnect keeps the new connection and reports a clear error when removing an old profile fails')

nmState.connections.push({uuid:'u-old3', id:'Dimensione-E92F', type:'802-11-wireless', ssid:'Dimensione-E92F', state:null, iface:null})
nmCalls = []; nmMissingRemove = new Set(['u-old3'])
await dispatch({op:'wifiConnect', ssid:'Dimensione-E92F', psk:'new password'})
assert.deepEqual(nmCalls.filter(c => c[0] === 'remove').map(c => c[1]), ['u-old', 'u-old3'])
nmMissingRemove = new Set()
nmState.connections = nmState.connections.filter(c => c.uuid !== 'u-old3')
console.log('ok: wifiConnect treats an already-missing old profile as removed, not a failure')

nmState.connections.push({uuid:'u-old4', id:'Dimensione-E92F', type:'802-11-wireless', ssid:'Dimensione-E92F', state:null, iface:null})
nmCalls = []; nmMissingRemove = new Set(['u-old']); nmFailRemove = new Set(['u-old4'])
await assert.rejects(dispatch({op:'wifiConnect', ssid:'Dimensione-E92F', psk:'new password'}), /old saved profile.*could not be removed: Cannot remove u-old4/)
nmMissingRemove = new Set(); nmFailRemove = new Set()
nmState.connections = nmState.connections.filter(c => c.uuid !== 'u-old4')
console.log('ok: wifiConnect reports the first real removal error\'s message, ignoring an already-missing profile among the same batch')

nmState.connections.push({uuid:'u-work', id:'Work VPN', type:'vpn', ssid:null, state:null, iface:null})
nmCalls = []
await dispatch({op:'vpn', uuid:'u-work', active:true})
assert.deepEqual(nmCalls, [['activate','u-work']])
nmCalls = []
await dispatch({op:'vpn', uuid:'u-work', active:false})
assert.deepEqual(nmCalls, [['deactivate','u-work']])
console.log('ok: vpn activates and deactivates a normal, non-Proton connection')

dbusCalls = []
result = await dispatch({op:'read',ids:['region.timezone','region.ntp','region.language','region.formats']})
assert.equal(result.values['region.timezone'].value, 'Europe/Rome')
assert.deepEqual(result.values['region.timezone'].choices.map(c => c.value), ['America/Argentina/Buenos_Aires','America/New_York','Europe/Rome'])
assert.equal(result.values['region.timezone'].choices[0].label, 'America / Argentina / Buenos Aires')
assert.equal(result.values['region.ntp'].value, true)
assert.equal(result.values['region.ntp'].note, 'Not synchronized yet')
assert.equal(result.values['region.language'].value, 'en_US.UTF-8')
assert.equal(result.values['region.formats'].value, 'it_IT.UTF-8')
assert.deepEqual(result.values['region.formats'].choices.map(c => c.value), ['C.UTF-8','en_US.UTF-8','it_IT.UTF-8'])
assert.equal(dbusCalls.length, 0)
console.log('ok: region reads come from files and D-Bus properties, without writes')

files.delete('/etc/locale.conf')
result = await dispatch({op:'read',ids:['region.timezone','region.ntp','region.language','region.formats']})
assert.equal(result.values['region.timezone'].value, 'Europe/Rome')
assert.equal(result.values['region.ntp'].value, true)
assert.equal(result.values['region.language'].value, 'C.UTF-8')
assert.equal(result.values['region.formats'].value, 'C.UTF-8')
files.set('/etc/locale.conf', 'LANG=en_US.UTF-8\nLC_TIME=it_IT.UTF-8\nLC_NUMERIC=it_IT.UTF-8\nLC_COLLATE=C.UTF-8\n')
localtimeMissing = true
result = await dispatch({op:'read',ids:['region.timezone']})
assert.equal(result.values['region.timezone'].value, 'UTC')
localtimeMissing = false
localtimeLink = null
result = await dispatch({op:'read',ids:['region.timezone']})
assert.equal(result.values['region.timezone'].value, 'UTC')
localtimeLink = '/usr/share/zoneinfo/posix/Europe/Rome'
result = await dispatch({op:'read',ids:['region.timezone']})
assert.equal(result.values['region.timezone'].value, 'Europe/Rome')
localtimeLink = '/usr/share/zoneinfo/Europe/Rome'
console.log('ok: missing region files fall back per field and zoneinfo prefixes are normalized')

await dispatch({op:'set',id:'region.timezone',value:'America/New_York'})
await dispatch({op:'set',id:'region.ntp',value:false})
await dispatch({op:'set',id:'region.formats',value:'en_US.UTF-8'})
await dispatch({op:'set',id:'region.language',value:'it_IT.UTF-8'})
assert.deepEqual(dbusCalls, [
    ['SetTimezone','(sb)',['America/New_York',true],true],
    ['SetNTP','(bb)',[false,true],true],
    ['SetLocale','(asb)',[['LANG=en_US.UTF-8','LC_TIME=en_US.UTF-8','LC_NUMERIC=en_US.UTF-8','LC_COLLATE=C.UTF-8','LC_MONETARY=en_US.UTF-8','LC_PAPER=en_US.UTF-8','LC_NAME=en_US.UTF-8','LC_ADDRESS=en_US.UTF-8','LC_TELEPHONE=en_US.UTF-8','LC_MEASUREMENT=en_US.UTF-8','LC_IDENTIFICATION=en_US.UTF-8'],true],true],
    ['SetLocale','(asb)',[['LANG=it_IT.UTF-8','LC_TIME=it_IT.UTF-8','LC_NUMERIC=it_IT.UTF-8','LC_COLLATE=C.UTF-8'],true],true],
])

dbusCalls = []
files.set('/etc/locale.conf', 'LANG=from_FILE.UTF-8\nLC_TIME=from_FILE.UTF-8\n')
dbusLocale = ['LC_TIME=fr_FR.UTF-8','LANG=de_DE.UTF-8','LC_COLLATE=C.UTF-8']
await dispatch({op:'set',id:'region.formats',value:'it_IT.UTF-8'})
assert.deepEqual(dbusCalls, [[
    'SetLocale','(asb)',[['LC_TIME=it_IT.UTF-8','LANG=de_DE.UTF-8','LC_COLLATE=C.UTF-8','LC_NUMERIC=it_IT.UTF-8','LC_MONETARY=it_IT.UTF-8','LC_PAPER=it_IT.UTF-8','LC_NAME=it_IT.UTF-8','LC_ADDRESS=it_IT.UTF-8','LC_TELEPHONE=it_IT.UTF-8','LC_MEASUREMENT=it_IT.UTF-8','LC_IDENTIFICATION=it_IT.UTF-8'],true],true,
]])
failingReadPath = '/etc/locale.conf'
dbusCalls = []
await dispatch({op:'set',id:'region.timezone',value:'America/New_York'})
await dispatch({op:'set',id:'region.ntp',value:false})
assert.deepEqual(dbusCalls.map(call => call[0]), ['SetTimezone','SetNTP'])
failingReadPath = ''
files.set('/etc/locale.conf', 'LANG=en_US.UTF-8\nLC_TIME=it_IT.UTF-8\nLC_NUMERIC=it_IT.UTF-8\nLC_COLLATE=C.UTF-8\n')
dbusLocale = ['LANG=en_US.UTF-8','LC_TIME=it_IT.UTF-8','LC_NUMERIC=it_IT.UTF-8','LC_COLLATE=C.UTF-8']
await assert.rejects(dispatch({op:'set',id:'region.timezone',value:'Mars/Olympus'}), /Unknown choice/)
await assert.rejects(dispatch({op:'set',id:'region.formats',value:'de_DE.ISO-8859-1'}), /Unknown choice/)
dbusDeny = true
await assert.rejects(dispatch({op:'set',id:'region.ntp',value:true}), {message: 'Authentication was cancelled; nothing changed.'})
dbusDeny = false
console.log('ok: region writes are interactive, merge locale keys, and report a cancelled prompt')

const mutations = () => events.filter(e => ['write', 'create', 'delete'].includes(e[0]))
const mine = id => `${base}/autostart/${id}`
const theirs = id => `/etc/xdg/autostart/${id}`
const put = (path, content) => { files.set(path, content); const dir = path.slice(0, path.lastIndexOf('/')); if (dirs.has(dir) && !dirs.get(dir).includes(path.slice(dir.length + 1))) dirs.get(dir).push(path.slice(dir.length + 1)) }
const drop = path => { files.delete(path); links.delete(path); const dir = path.slice(0, path.lastIndexOf('/')); if (dirs.has(dir)) dirs.set(dir, dirs.get(dir).filter(name => name !== path.slice(dir.length + 1))) }
const link = (path, target) => { links.set(path, target); const dir = path.slice(0, path.lastIndexOf('/')); if (dirs.has(dir)) dirs.get(dir).push(path.slice(dir.length + 1)) }
const startupApps = async () => Object.fromEntries((await dispatch({op:'read',ids:[],startup:true})).startup.apps.map(a => [a.id, a]))
events = []
result = await dispatch({op:'read',ids:[],startup:true})
const apps = Object.fromEntries(result.startup.apps.map(a => [a.id, a]))
assert.deepEqual(result.startup.session, ['waybar', 'systemctl --user start …'])
assert.equal(apps['nm-applet.desktop'].status.state, 'running')
assert.equal(apps['arch-update-tray.desktop'].status.label, 'Not installed: arch-update')
assert.equal(apps['manual.desktop'].origin, 'override')
assert.deepEqual(result.startup.available, [{id:'firefox.desktop', name:'Firefox'}])
assert.equal(mutations().length, 0)
console.log('ok: startup read lists session, apps with status, and addable apps')

await dispatch({op:'autostart',action:'disable',id:'blueman.desktop'})
assert.equal(files.get(base+'/autostart/blueman.desktop'), '[Desktop Entry]\nType=Application\nName=Blueman Applet\nHidden=true\n')
dirs.get(base+'/autostart').push('blueman.desktop')
await dispatch({op:'autostart',action:'enable',id:'blueman.desktop'})
assert.equal(files.has(base+'/autostart/blueman.desktop'), false)
dirs.set(base+'/autostart', dirs.get(base+'/autostart').filter(n => n !== 'blueman.desktop'))
console.log('ok: disabling a system entry writes the minimal override; enabling deletes it')


const manualBefore = files.get(base+'/autostart/manual.desktop')
events = []
await assert.rejects(dispatch({op:'autostart',action:'enable',id:'manual.desktop'}), /Not an application entry/)
assert.equal(files.get(base+'/autostart/manual.desktop'), manualBefore)
await assert.rejects(dispatch({op:'autostart',action:'remove',id:'nm-applet.desktop'}), /Only apps you added/)
await assert.rejects(dispatch({op:'autostart',action:'disable',id:'../../etc/passwd'}), /no longer exists/)
await assert.rejects(dispatch({op:'autostart',action:'explode',id:'nm-applet.desktop'}), /Unknown startup action/)
assert.equal(mutations().length, 0)
files.set(base+'/autostart/manual.desktop', '[Desktop Entry]\nType=Application\nName=Manual\nExec=manual\nHidden=true\n')
await dispatch({op:'autostart',action:'enable',id:'manual.desktop'})
assert.equal(files.get(base+'/autostart/manual.desktop'), '[Desktop Entry]\nType=Application\nName=Manual\nExec=manual\n')
files.set(base+'/autostart/manual.desktop', manualBefore)
console.log('ok: hand-edited overrides, system removals, unknown ids and actions are refused')

// A customised override (its own Exec) is the user's work: Remove is refused, nothing is touched.
{
    const custom = '[Desktop Entry]\nType=Application\nName=Manual\nExec=manual --my-flag\n'
    files.set(base+'/autostart/manual.desktop', custom)
    events = []
    await assert.rejects(dispatch({op:'autostart',action:'remove',id:'manual.desktop'}), /is your own version of this entry/)
    assert.equal(files.get(base+'/autostart/manual.desktop'), custom)
    assert.equal(mutations().length, 0)
    files.set(base+'/autostart/manual.desktop', manualBefore)
}
console.log('ok: a customised override cannot be removed from the panel')

// --- Startup page safety: links, exclusive creation, encodings, scopes ------------------
put('/elsewhere/target.desktop', '[Desktop Entry]\nType=Application\nName=Target\nExec=manual\n')
link(mine('linked.desktop'), '/elsewhere/target.desktop')
link(mine('dangling.desktop'), '/elsewhere/nowhere.desktop')
link(mine('blueman.desktop'), '/elsewhere/nowhere.desktop')
events = []
let linkApps = await startupApps()
assert.equal(linkApps['linked.desktop'].link, true)
assert.equal(linkApps['linked.desktop'].name, 'Target')
// A dangling link is ignored, as systemd ignores it: it neither lists nor masks anything.
assert.equal(linkApps['dangling.desktop'], undefined)
assert.equal(linkApps['blueman.desktop'].origin, 'system')
assert.equal(linkApps['blueman.desktop'].scope, '')
for (const action of ['enable', 'disable', 'remove'])
    await assert.rejects(dispatch({op:'autostart',action,id:'linked.desktop'}), /~\/\.config\/autostart\/linked\.desktop is a link; edit it by hand/)
await assert.rejects(dispatch({op:'autostart',action:'disable',id:'dangling.desktop'}), /no longer exists/)
// Disabling blueman would create its override exclusively: the dangling link there refuses it.
await assert.rejects(dispatch({op:'autostart',action:'disable',id:'blueman.desktop'}), /already exists/)
link(mine('firefox.desktop'), '/elsewhere/nowhere.desktop')
await assert.rejects(dispatch({op:'autostartAdd',app:'firefox.desktop'}), /Already in startup apps/)
assert.equal(mutations().length, 0)
assert.equal(files.has('/elsewhere/nowhere.desktop'), false)
assert.equal(files.get('/elsewhere/target.desktop'), '[Desktop Entry]\nType=Application\nName=Target\nExec=manual\n')
for (const id of ['linked.desktop', 'dangling.desktop', 'blueman.desktop', 'firefox.desktop']) drop(mine(id))
console.log('ok: links are never written through; a dangling link is ignored like systemd ignores it')

raceOnce.add(mine('blueman.desktop'))
await assert.rejects(dispatch({op:'autostart',action:'disable',id:'blueman.desktop'}), /~\/\.config\/autostart\/blueman\.desktop already exists/)
raceOnce.add(mine('firefox.desktop'))
await assert.rejects(dispatch({op:'autostartAdd',app:'firefox.desktop'}), /~\/\.config\/autostart\/firefox\.desktop already exists/)
assert.equal(files.has(mine('blueman.desktop')) || files.has(mine('firefox.desktop')), false)
console.log('ok: disabling a system entry and adding an app create the file exclusively')

put(theirs('hiddensys.desktop'), '[Desktop Entry]\nType=Application\nName=Hidden sys\nExec=manual\nHidden=true\nComment=keep\n')
linkApps = await startupApps()
assert.equal(linkApps['hiddensys.desktop'].enabled, false)
assert.equal(linkApps['hiddensys.desktop'].scope, '')
events = []
await dispatch({op:'autostart',action:'enable',id:'hiddensys.desktop'})
assert.deepEqual(mutations(), [['create', mine('hiddensys.desktop')]])
dirs.get(base+'/autostart').push('hiddensys.desktop')
assert.equal(files.get(mine('hiddensys.desktop')), '[Desktop Entry]\nType=Application\nName=Hidden sys\nExec=manual\nComment=keep\n')
assert.equal((await startupApps())['hiddensys.desktop'].enabled, true)
drop(mine('hiddensys.desktop')); drop(theirs('hiddensys.desktop'))
put(theirs('latinsys.desktop'), Buffer.from('[Desktop Entry]\nType=Application\nName=Caf\xe9\nExec=manual\nHidden=true\n', 'latin1'))
events = []
await assert.rejects(dispatch({op:'autostart',action:'enable',id:'latinsys.desktop'}), /\/etc\/xdg\/autostart\/latinsys\.desktop is not UTF-8; edit it by hand/)
assert.equal(mutations().length, 0)
drop(theirs('latinsys.desktop'))
console.log('ok: enabling a Hidden system entry writes an override without Hidden')

put(theirs('renamed.desktop'), '[Desktop Entry]\nType=Application\nName=New Name\nExec=manual\n')
put(mine('renamed.desktop'), '[Desktop Entry]\nType=Application\nName=Old Name\nHidden=true\n')
linkApps = await startupApps()
assert.equal(linkApps['renamed.desktop'].name, 'New Name')
assert.equal(linkApps['renamed.desktop'].binary, 'manual')
assert.equal(linkApps['renamed.desktop'].scope, '')
assert.equal(linkApps['renamed.desktop'].enabled, false)
assert.equal(linkApps['renamed.desktop'].status.label, 'Hidden by ' + autostartUserDir + '/renamed.desktop')
assert.equal(linkApps['renamed.desktop'].removable, true)
assert.equal(linkApps['nm-applet.desktop'].removable, false)
events = []
await assert.rejects(dispatch({op:'autostart',action:'enable',id:'renamed.desktop'}), /~\/\.config\/autostart\/renamed\.desktop was written by hand; remove it there to restore the system entry/)
assert.equal(mutations().length, 0)
await dispatch({op:'autostart',action:'remove',id:'renamed.desktop'})
assert.deepEqual(mutations(), [['delete', mine('renamed.desktop')]])
assert.equal(files.has(theirs('renamed.desktop')), true)
drop(theirs('renamed.desktop'))
console.log('ok: a vendor-renamed override is described by the system file, refused on enable, and removable')

put(mine('latin.desktop'), Buffer.from('[Desktop Entry]\nType=Application\nName=Caf\xe9\nExec=manual\n', 'latin1'))
const latin = files.get(mine('latin.desktop'))
events = []
await assert.rejects(dispatch({op:'autostart',action:'disable',id:'latin.desktop'}), /~\/\.config\/autostart\/latin\.desktop is not UTF-8; edit it by hand/)
assert.equal(mutations().length, 0)
assert.equal(files.get(mine('latin.desktop')), latin)
drop(mine('latin.desktop'))
put(mine('bom.desktop'), '﻿[Desktop Entry]\nType=Application\nName=Bom\nExec=manual\n')
await dispatch({op:'autostart',action:'disable',id:'bom.desktop'})
assert.equal(files.get(mine('bom.desktop')), '﻿[Desktop Entry]\nType=Application\nName=Bom\nExec=manual\nHidden=true\n')
await dispatch({op:'autostart',action:'enable',id:'bom.desktop'})
assert.equal(files.get(mine('bom.desktop')), '﻿[Desktop Entry]\nType=Application\nName=Bom\nExec=manual\n')
drop(mine('bom.desktop'))
console.log('ok: edits refuse non-UTF-8 files and keep a leading BOM')

put(theirs('kde.desktop'), '[Desktop Entry]\nType=Application\nName=KDE thing\nExec=manual\nNotShowIn=Hyprland;\n')
put(mine('perm.desktop'), '[Desktop Entry]\nType=Application\nName=Perm\nExec=manual\n')
failingReadPath = mine('perm.desktop')
linkApps = await startupApps()
assert.equal(linkApps['perm.desktop'].scope, 'Unreadable file in ~/.config/autostart')
assert.equal(linkApps['perm.desktop'].link, false)
events = []
for (const action of ['enable', 'disable']) {
    await assert.rejects(dispatch({op:'autostart',action,id:'kde.desktop'}), /Not for Hyprland/)
    await assert.rejects(dispatch({op:'autostart',action,id:'perm.desktop'}), /Unreadable file in ~\/\.config\/autostart/)
    await assert.rejects(dispatch({op:'autostart',action,id:'manual.desktop'}), /Not an application entry/)
}
assert.equal(mutations().length, 0)
await dispatch({op:'autostart',action:'remove',id:'perm.desktop'})
assert.deepEqual(mutations(), [['delete', mine('perm.desktop')]])
failingReadPath = ''
drop(theirs('kde.desktop'))
console.log('ok: entries with a scope refuse enable and disable server-side; remove stays allowed')

put(theirs('plain.desktop'), '[Desktop Entry]\nType=Application\nName=Plain\nExec=plainbin\n')
put(theirs('viaLink.desktop'), '[Desktop Entry]\nType=Application\nName=Via link\nExec=linkbin\n')
put(theirs('absolute.desktop'), '[Desktop Entry]\nType=Application\nName=Absolute\nExec=/usr/bin/plainbin\n')
put('/usr/bin/plainbin', '')
link('/usr/bin/linkbin', '/usr/bin/manual')
linkApps = await startupApps()
assert.equal(linkApps['plain.desktop'].installed, false)
assert.equal(linkApps['plain.desktop'].status.label, 'Not installed: plainbin')
assert.equal(linkApps['absolute.desktop'].installed, false)
assert.equal(linkApps['viaLink.desktop'].installed, true)
for (const id of ['plain', 'viaLink', 'absolute']) drop(theirs(id + '.desktop'))
drop('/usr/bin/plainbin'); links.delete('/usr/bin/linkbin')
console.log('ok: a binary on PATH must be an executable regular file')

put(theirs('quotedpath.desktop'), '[Desktop Entry]\nType=Application\nName=Quoted path\nExec=toolx\nOnlyShowIn=Hyprland;\n')
put("/opt/it's/bin/toolx", ''); execs.add("/opt/it's/bin/toolx")
showEnvironment = "XDG_CURRENT_DESKTOP=$'Hypr\\x6cand'\nPATH=$'/opt/it\\'s/bin:/usr/bin'\n"
linkApps = await startupApps()
assert.equal(linkApps['quotedpath.desktop'].scope, '')
assert.equal(linkApps['quotedpath.desktop'].installed, true)
showEnvironment = 'XDG_CURRENT_DESKTOP=Hyprland\nPATH=/usr/local/bin:/usr/bin\n'
drop(theirs('quotedpath.desktop')); drop("/opt/it's/bin/toolx"); execs.delete("/opt/it's/bin/toolx")
console.log("ok: show-environment $'...' values are unquoted")

failingReadPath = base + '/hypr/config/setup/autostart.lua'
result = await dispatch({op:'read',ids:['appearance.blur','power.lock'],startup:true})
assert.match(result.startup.error, /Permission denied/)
assert.equal(typeof result.values['appearance.blur'].value, 'boolean')
assert.equal(result.values['power.lock'].error, undefined)
failingReadPath = ''
console.log("ok: a failing startup read degrades to an error on the Startup view only")

events = []
await assert.rejects(dispatch({op:'autostartAdd',app:'nm-applet.desktop'}), /Already in startup apps/)
await assert.rejects(dispatch({op:'autostartAdd',app:'hidden-app.desktop'}), /Not shown in menus/)
await assert.rejects(dispatch({op:'autostartAdd',app:'noexec.desktop'}), /Would not start at login: No command to run/)
await assert.rejects(dispatch({op:'autostartAdd',app:'kdeonly.desktop'}), /Only for KDE/)
await assert.rejects(dispatch({op:'autostartAdd',app:'notonhypr.desktop'}), /Not for Hyprland/)
await assert.rejects(dispatch({op:'autostartAdd',app:'ghost.desktop'}), /not installed/)
assert.equal(mutations().length, 0)
console.log('ok: add refuses present, hidden, commandless and inapplicable apps')

await dispatch({op:'autostartAdd',app:'firefox.desktop'})
assert.equal(files.get(mine('firefox.desktop')), files.get('/usr/share/applications/firefox.desktop'))
dirs.get(base+'/autostart').push('firefox.desktop')
await assert.rejects(dispatch({op:'autostartAdd',app:'firefox.desktop'}), /Already in startup apps/)
await dispatch({op:'autostart',action:'remove',id:'firefox.desktop'})
assert.equal(files.has(mine('firefox.desktop')), false)
console.log('ok: add copies the desktop file; remove deletes only user entries')

assert.deepEqual([...files.keys()].filter(path => /\/\.[^/]*\.tmp$/.test(path)), [], 'no temporary autostart file is ever left behind')
console.log('ok: new autostart files are published whole; no temporary file is left behind')

{
    // The older direct-hyprlock lock listener still parses.
    const idle = base + '/hypr/hypridle.conf', before = files.get(idle)
    const current = (await dispatch({op:'read', ids:['power.lock']})).values['power.lock'].value
    assert.equal(typeof current, 'number')
    files.set(idle, before.replace('on-timeout = loginctl lock-session', 'on-timeout = hyprlock'))
    const result = await dispatch({op:'read', ids:['power.lock']})
    assert.equal(result.values['power.lock'].value, current)
    files.set(idle, before)
}
console.log('ok: the lock listener is found whether it runs hyprlock or loginctl lock-session')

// About uses synthetic data only; full reads seek into the bounded log tail.
const aboutSources = {
    '/etc/os-release':'PRETTY_NAME="Example Linux"', '/proc/sys/kernel/osrelease':'6.12.4-1-example\n', '/proc/uptime':'28260.50 99999.00\n',
    '/proc/cpuinfo':'processor : 0\nmodel name : Example CPU\ncpu cores : 1\n', '/proc/meminfo':'MemTotal: 16000000 kB\n',
    '/var/log/pacman.log':'[2025-08-14T12:03:26+0200] [PACMAN] Running pacman\n' + 'x'.repeat(300000) + '\n[2026-01-05T11:15:00+0100] [PACMAN] starting full system upgrade\n[2026-01-05T11:16:00+0100] [ALPM] transaction completed\n',
    '/sys/class/dmi/id/sys_vendor':'Example Corporation', '/sys/class/dmi/id/product_name':'System Product Name',
    '/sys/class/dmi/id/board_vendor':'Example Corporation', '/sys/class/dmi/id/board_name':'Example Board'}
for (const [path,text] of Object.entries(aboutSources)) files.set(path,text)
aboutAttributes.set('/',{'filesystem::size':999e9,'filesystem::free':750e9,'filesystem::used':199e9,'time::created':1735732800})
mockEnv.XDG_CURRENT_DESKTOP = 'Hyprland:Example'; mockEnv.XDG_SESSION_TYPE = 'wayland'
events = []
let aboutReply = await dispatch({op:'read',ids:[],about:'summary'})
assert.deepEqual(aboutReply.about,{user:'alex',realName:'Alex Example',host:'workstation',os:'Example Linux',kernel:'6.12.4-1-example',hyprland:'0.54.0',uptimeSeconds:28260.5,avatar:''})
assert.equal(events.some(e => e[0] === 'lspci'),false)
assert.equal(aboutStreamReads.length,0,'summary does not read the pacman log')
aboutReply = await dispatch({op:'read',ids:[],about:'full'})
assert.equal(aboutReply.about.session,'Hyprland on Wayland')
assert.equal(aboutReply.about.installed,'2025-08-14T10:03:26.000Z')
assert.equal(aboutReply.about.lastUpgrade,'2026-01-05T10:15:00.000Z')
assert.deepEqual(aboutReply.about.cpu,{name:'Example',cores:1,threads:1})
assert.equal(aboutReply.about.memoryGB,16)
assert.deepEqual(aboutReply.about.gpus,['NVIDIA GeForce RTX 3070'])
assert.deepEqual(aboutReply.about.storage,{used:199,total:999,fraction:199/999})
assert.deepEqual(aboutReply.about.machine,{label:'Motherboard',value:'Example Example Board'})
assert.ok(aboutStreamReads.some(e => e[0] === 'seek' && e[1] > 0))
assert.ok(aboutStreamReads.filter(e => e[0] === 'read').every(e => e[1] <= 256*1024))
failAboutTail = true
const partialLog = (await dispatch({op:'read',ids:[],about:'full'})).about
assert.equal(partialLog.installed,'2025-08-14T10:03:26.000Z','tail errors preserve the first-line install timestamp')
assert.equal(partialLog.lastUpgrade,null)
assert.equal(partialLog.memoryGB,16,'unrelated sources survive log errors')
failAboutTail = false
files.set('/fixture/.face','image')
assert.equal((await dispatch({op:'read',ids:[],about:'summary'})).about.avatar,'/fixture/.face')
const accountIcon = '/var/lib/AccountsService/icons/alex'
files.set(accountIcon,'image')
assert.equal((await dispatch({op:'read',ids:[],about:'summary'})).about.avatar,'/fixture/.face','home face takes priority')
unreadableAvatars.add('/fixture/.face')
assert.equal((await dispatch({op:'read',ids:[],about:'summary'})).about.avatar,accountIcon,'unreadable home face falls back to the icon file')
files.delete('/fixture/.face'); unreadableAvatars.clear()
assert.equal((await dispatch({op:'read',ids:[],about:'summary'})).about.avatar,accountIcon)
unreadableAvatars.add(accountIcon)
assert.equal((await dispatch({op:'read',ids:[],about:'summary'})).about.avatar,'')
unreadableAvatars.clear(); files.delete(accountIcon)
files.set('/sys/class/dmi/id/sys_vendor','LENOVO')
files.set('/sys/class/dmi/id/product_name','21CBCTO1WW')
files.set('/sys/class/dmi/id/product_version','ThinkPad X1 Carbon Gen 10')
assert.deepEqual((await dispatch({op:'read',ids:[],about:'full'})).about.machine,{label:'Model',value:'Lenovo ThinkPad X1 Carbon Gen 10'})
files.delete('/sys/class/dmi/id/product_version')
const originalHomeDir = settingsMocks.GLib.get_home_dir
settingsMocks.GLib.get_home_dir = () => { throw new Error('Avatar source failed') }
try {
    const reply = await dispatch({op:'read',ids:['power.lock'],about:'summary'})
    assert.equal(reply.about,null)
    assert.equal(typeof reply.values['power.lock'].value,'number','settings values survive an unexpected About failure')
    assert.equal(reply.values['power.lock'].error,undefined)
} finally { settingsMocks.GLib.get_home_dir = originalHomeDir }
files.delete('/var/log/pacman.log')
assert.equal((await dispatch({op:'read',ids:[],about:'full'})).about.installed,'2025-01-01T12:00:00.000Z')
for (const path of Object.keys(aboutSources)) files.delete(path)
aboutAttributes.clear(); aboutCommandsMissing = true
const missingAbout = (await dispatch({op:'read',ids:[],about:'full'})).about
for (const key of ['os','kernel','hyprland','uptimeSeconds','installed','lastUpgrade','cpu','memoryGB','gpus','storage','machine']) assert.equal(missingAbout[key],null,key)
assert.equal(missingAbout.avatar,'')
assert.equal(missingAbout.error,undefined)
assert.equal(events.some(e => e[0] === 'accounts-dbus'),false,'About never contacts AccountsService, even for missing or unreadable avatars')
console.log('ok: about backend')

// Calendar page: options that may be missing read as their defaults, the account and calendars come from the keyring and cal.sh.
events = []
files.delete(base+'/options/bar-agenda')
const calendarDefaults = await dispatch({op:'read',ids:['bar.agenda','calendar.alert','calendar.duration','calendar.default']})
assert.equal(calendarDefaults.values['bar.agenda'].value,'soon')
assert.equal(calendarDefaults.values['bar.agenda'].reset,false)
assert.equal(calendarDefaults.values['calendar.alert'].value,'15m')
assert.equal(calendarDefaults.values['calendar.duration'].value,'60')
assert.deepEqual(calendarDefaults.values['calendar.default'],{value:'',reset:false,choices:[]},'no listing offers no calendar')
console.log('ok: calendar options read their defaults when unset')

calendarsListing = JSON.stringify([{name:'Work',color:'#ff0000',writable:true},{name:'Holidays',color:'',writable:false},{name:'Home',color:'#00ff00',writable:true}])
files.set(base+'/options/calendar-hidden','Home\n')
const calendarPage = await dispatch({op:'read',ids:['calendar.default']})
assert.deepEqual(calendarPage.values['calendar.default'].choices,[{label:'Work',value:'Work'},{label:'Home',value:'Home'}],'only writable calendars are offered')
assert.equal(calendarPage.values['calendar.default'].value,'Work','an unset default is the first writable calendar, as the card picks it')
keyringAccount = 'me@icloud.com'
events = []
const shown = await dispatch({op:'calendarStatus'})
assert.equal(shown.calendar.account,'me@icloud.com')
assert.deepEqual(shown.calendar.calendars.map(c => [c.name,c.shown]),[['Work',true],['Holidays',true],['Home',false]])
keyringAccount = ''
const signedOut = await dispatch({op:'calendarStatus'})
assert.deepEqual(signedOut.calendar.calendars,[])
assert.equal(signedOut.calendar.account,'')
console.log('ok: calendar status lists the writable and shown calendars')

events = []
await dispatch({op:'calendarSignIn',appleId:' me@icloud.com ',password:'abcd-efgh'})
const signIn = events.find(e => e[0] === 'stdin')
assert.equal(signIn[1][1].endsWith('/scripts/calendar/setup.sh'),true)
assert.deepEqual(signIn[1].slice(2),['--sign-in','--stdin'])
assert.equal(signIn[1].join(' ').includes('abcd-efgh'),false,'the password is never in argv')
assert.equal(signIn[2],'me@icloud.com\nabcd-efgh\n')
signInError = 'Sign-in rejected: check the Apple ID and the app-specific password.'
await assert.rejects(dispatch({op:'calendarSignIn',appleId:'me@icloud.com',password:'wrong'}),/Sign-in rejected/)
signInError = ''
console.log('ok: sign-in sends credentials on stdin only')

events = []
await dispatch({op:'calendarSignOut'})
assert.ok(events.some(e => e[0] === 'bash' && String(e[1]).endsWith('/scripts/calendar/setup.sh') && e[2] === '--sign-out'))
console.log('ok: sign-out runs setup.sh --sign-out')

events = []
await dispatch({op:'calendarShow',name:'Work',shown:false})
assert.equal(files.get(base+'/options/calendar-hidden'),'Home\nWork\n')
assert.ok(events.some(e => e[0] === 'bash' && String(e[1]).endsWith('/scripts/calendar/sync.sh') && e[2] === '--render'))
await dispatch({op:'calendarShow',name:'Home',shown:true})
assert.equal(files.get(base+'/options/calendar-hidden'),'Work\n')
await assert.rejects(dispatch({op:'calendarShow',name:'a\nb',shown:true}),/Invalid calendar name/)
// A failed render puts the previous list back (the rollback's own render succeeds), and a list that did not exist is removed again.
failCalendarRenders = 1
await assert.rejects(dispatch({op:'calendarShow',name:'Home',shown:false}),/Previous settings restored/)
assert.equal(files.get(base+'/options/calendar-hidden'),'Work\n','a failed render restores the previous bytes')
files.delete(base+'/options/calendar-hidden')
failCalendarRenders = 1
await assert.rejects(dispatch({op:'calendarShow',name:'Work',shown:false}),/Previous settings restored/)
assert.equal(files.has(base+'/options/calendar-hidden'),false,'a failed render removes the file it created')
console.log('ok: calendar visibility edits the hidden list and re-renders')
console.log('ok: a failed calendar render restores the hidden list')

events = []
await dispatch({op:'set',id:'calendar.default',value:'Work'})
assert.equal(files.get(base+'/options/calendar-default'),'Work\n', 'a never-set calendar-default is created by its first save')
await assert.rejects(dispatch({op:'set',id:'calendar.default',value:'Holidays'}),/Unknown choice/)
await dispatch({op:'set',id:'calendar.alert',value:'1h'})
assert.equal(files.get(base+'/options/calendar-alert'),'1h\n')
assert.equal(events.filter(e => e[0] === 'bash' && String(e[1]).endsWith('/scripts/calendar/sync.sh') && e[2] === '--render').length,2,'one render per save')
console.log('ok: calendar defaults save and re-render')
