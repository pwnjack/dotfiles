// A page's reader (Devices, Calendar, Sound) may finish after the page was hidden or the
// panel closed; only a completion from the run started under the current generation may be applied.
export function fresh(startedGeneration, currentGeneration, shown) {
    return shown && startedGeneration === currentGeneration;
}

export function parse(text) {
    try { return JSON.parse(text); }
    catch (error) { return {error: String(error)}; }
}
