// Runtime machine information parsing and presentation, shared by GJS, QML and Node.
// No I/O here: an unreadable source is handled independently by the backend.
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December']
const text = value => typeof value === 'string' ? value.trim() : ''
function date(value) {
    if (value === null || value === undefined || value === '') return null
    const result = new Date(value)
    return Number.isFinite(result.getTime()) ? result : null
}
const fullDate = value => `${value.getDate()} ${MONTHS[value.getMonth()]} ${value.getFullYear()}`

export function installedFromPacmanLog(firstLine) {
    const match = text(firstLine).match(/^\[([^\]]+)\]/)
    const parsed = match ? date(match[1]) : null
    return parsed ? parsed.toISOString() : null
}
export function lastFullUpgrade(logText) {
    let latest = null, pending = null
    for (const line of text(logText).split('\n')) {
        // A new pacman invocation ends a declined or empty upgrade's claim on the
        // next completed transaction.
        if (line.includes('[PACMAN] Running')) pending = null
        if (line.includes('starting full system upgrade')) {
            pending = installedFromPacmanLog(line)
        } else if (line.includes('[ALPM] transaction completed') && pending) {
            latest = pending
            pending = null
        }
    }
    return latest
}
export function osName(osReleaseText) {
    const values = {}
    for (const line of text(osReleaseText).split('\n')) {
        const match = line.match(/^(PRETTY_NAME|NAME)=(.*)$/)
        if (match) values[match[1]] = match[2].trim().replace(/^(["'])(.*)\1$/, '$2')
    }
    return values.PRETTY_NAME || values.NAME || ''
}
export function cpuInfo(cpuinfoText) {
    const input = text(cpuinfoText)
    const model = input.match(/^model name\s*:\s*(.*)$/m)
    const cores = input.match(/^cpu cores\s*:\s*(\d+)/m)
    const processors = input.match(/^processor\s*:/gm)
    return {
        name: model ? model[1].replace(/\((R|TM)\)/gi, '').replace(/\bCPU\b/g, '')
            .replace(/@\s*[\d.]+\s*GHz/gi, '').replace(/\b\d+-Core Processor\b/gi, '')
            .replace(/\s+/g, ' ').trim() : '',
        cores: cores && Number(cores[1]) > 0 ? Number(cores[1]) : null,
        threads: processors ? processors.length : null,
    }
}
export function memoryGB(meminfoText) {
    const match = text(meminfoText).match(/^MemTotal:\s*(\d+)\s*kB/m)
    return match && Number(match[1]) > 0 ? Math.ceil(Number(match[1]) / 1048576) : null
}
export function vendorShort(name) {
    const value = text(name)
    for (const [pattern, short] of [
        [/^NVIDIA\b/i, 'NVIDIA'], [/^Advanced Micro Devices\b/i, 'AMD'], [/^Intel\b/i, 'Intel'],
        [/^ASUSTeK\b/i, 'ASUS'], [/^Micro-Star\b/i, 'MSI'], [/^Gigabyte\b/i, 'Gigabyte'],
        [/^LENOVO$/i, 'Lenovo'], [/^Dell\b/i, 'Dell'], [/^(HP|Hewlett-Packard)\b/i, 'HP'],
    ]) if (pattern.test(value)) return short
    return value.replace(/(?:\s*(?:Inc\.?|Corporation|Co\.,?\s*Ltd\.?|Ltd\.?|,))+$/gi, '').trim()
}
export function gpus(lspciMM) {
    const result = []
    for (const line of text(lspciMM).split('\n')) {
        const fields = []
        const quoted = /"((?:[^"\\]|\\.)*)"/g
        let match
        while ((match = quoted.exec(line))) fields.push(match[1].replace(/\\(["\\])/g, '$1'))
        if (!['VGA compatible controller', '3D controller', 'Display controller'].includes(fields[0]) || !fields[2]) continue
        const brackets = fields[2].match(/\[([^\]]+)\]/)
        result.push([vendorShort(fields[1]), brackets ? brackets[1] : fields[2]].filter(Boolean).join(' '))
    }
    return result
}
const PLACEHOLDERS = ['', 'System manufacturer', 'System Product Name', 'To be filled by O.E.M.',
    'Default string', 'Not Applicable', 'Standard PC'].map(value => value.toLowerCase())
const real = value => !PLACEHOLDERS.includes(text(value).toLowerCase())
export function machine({sysVendor, productName, productVersion, boardVendor, boardName} = {}) {
    const product = text(productName), board = text(boardName)
    const isBoard = !real(product) || !real(sysVendor) || (real(board) && board.includes(product))
    if (isBoard) {
        if (real(board)) return {label: 'Motherboard', value: [real(boardVendor) ? vendorShort(boardVendor) : '', board].filter(Boolean).join(' ')}
        return null
    }
    // Lenovo's product_name is a machine-type code; product_version carries the model.
    const model = /^LENOVO$/i.test(text(sysVendor)) && real(productVersion) ? text(productVersion) : product
    return {label: 'Model', value: [vendorShort(sysVendor), model].filter(Boolean).join(' ')}
}
// `compact` drops the spaces ("7h 51m") for the narrow sidebar summary.
export function formatUptime(seconds, compact = false) {
    if (typeof seconds !== 'number' || !Number.isFinite(seconds) || seconds < 0) return ''
    const minutes = Math.floor(seconds / 60), hours = Math.floor(minutes / 60), days = Math.floor(hours / 24)
    const unit = compact ? '' : ' '
    return days ? `${days}${unit}d ${hours % 24}${unit}h` : hours ? `${hours}${unit}h ${minutes % 60}${unit}m` : `${minutes}${unit}m`
}
export function formatInstalled(iso, now = Date.now()) {
    const installed = date(iso), today = date(now)
    if (!installed || !today) return ''
    const months = Math.max(0, (today.getFullYear() - installed.getFullYear()) * 12 + today.getMonth() - installed.getMonth())
    const years = Math.floor(months / 12), rest = months % 12
    const relative = years ? `${years} ${years === 1 ? 'year' : 'years'}${rest ? `, ${rest} ${rest === 1 ? 'month' : 'months'}` : ''} ago`
        : months ? `${months} ${months === 1 ? 'month' : 'months'} ago` : 'less than a month ago'
    return fullDate(installed) + ' · ' + relative
}
export function formatLastUpgrade(iso, now = Date.now()) {
    const upgrade = date(iso), today = date(now)
    if (!upgrade || !today) return ''
    // Compare calendar dates across DST boundaries, rather than elapsed 24-hour blocks.
    const calendarDay = d => Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) / 86400000
    const days = calendarDay(today) - calendarDay(upgrade)
    const time = String(upgrade.getHours()).padStart(2, '0') + ':' + String(upgrade.getMinutes()).padStart(2, '0')
    return days === 0 ? 'Today, ' + time : days === 1 ? 'Yesterday, ' + time
        : days >= 2 && days <= 30 ? `${days} days ago` : fullDate(upgrade)
}
export function storageGB(sizeBytes, usedBytes) {
    if (typeof sizeBytes !== 'number' || typeof usedBytes !== 'number' || !Number.isFinite(sizeBytes) || !Number.isFinite(usedBytes) || sizeBytes <= 0 || usedBytes < 0) return null
    const used = Math.min(sizeBytes, usedBytes)
    return {used: Math.round(used / 1e9), total: Math.round(sizeBytes / 1e9), fraction: used / sizeBytes}
}
export function sessionName(desktop, type) {
    const name = text(desktop).split(':')[0], session = text(type)
    const label = session === 'wayland' ? 'Wayland' : session === 'x11' ? 'X11' : session
    return [name, label].filter(Boolean).join(' on ')
}
