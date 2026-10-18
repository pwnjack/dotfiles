// Sound page helpers (device names and hidden devices), free of GJS so node can test them.
import { deriveLabel, parseHidden, parseNames } from '../sound/model.mjs'
export { deriveLabel, parseHidden, parseNames }

const MAX_NAME = 40
// validName(text) -> the trimmed custom name; an empty result means "no custom name".
export function validName(text) {
    const name = String(text).trim()
    if (/[\r\n\t]/.test(name)) throw new Error('Names cannot contain line breaks or tabs')
    if (name.length > MAX_NAME) throw new Error(`Names are at most ${MAX_NAME} characters`)
    return name
}
// toggleHidden(text, nodeName, shown) -> the new options/sound-hidden text.
export function toggleHidden(text, nodeName, shown) {
    const names = parseHidden(text).filter(n => n !== nodeName)
    if (!shown) names.push(nodeName)
    return names.length ? names.join('\n') + '\n' : ''
}
// setName(text, nodeName, label) -> the new options/sound-names text: node.name <TAB> label,
// sorted by node name. An empty label removes the device's line.
export function setName(text, nodeName, label) {
    const names = parseNames(text)
    if (label.trim()) names[nodeName] = label.trim()
    else delete names[nodeName]
    const lines = Object.keys(names).sort().map(n => `${n}\t${names[n]}`)
    return lines.length ? lines.join('\n') + '\n' : ''
}
