// Sound page helpers (device names and hidden devices), free of GJS so node can test them.
import { deriveLabel, parseHidden, parseNames } from '../sound/model.mjs'
export { deriveLabel, parseHidden, parseNames }

const MAX_NAME = 40
// validName(text) -> the trimmed custom name; an empty result means "no custom name".
export function validName(text) {
    // Checked before trimming, so a control character at either edge is refused rather than dropped.
    if (/[\r\n\t]/.test(String(text))) throw new Error('Names cannot contain line breaks or tabs')
    const name = String(text).trim()
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
// sorted by node name. An empty label removes the device's line. `__proto__` passes the
// node-name pattern but cannot be a key of the plain object parseNames returns, so it is refused.
export function setName(text, nodeName, label) {
    if (nodeName === '__proto__') throw new Error('Invalid device name')
    const names = parseNames(text)
    if (label.trim()) names[nodeName] = label.trim()
    else delete names[nodeName]
    const lines = Object.keys(names).sort().map(n => `${n}\t${names[n]}`)
    return lines.length ? lines.join('\n') + '\n' : ''
}
