// Presentation rules for the settings panel, free of QML and I/O so Node can test
// them and QML can import them (as it does network.mjs): the sidebar's groups, the
// sections a page or a search draws, mirrored sliders, dependent rows, and the
// structure catalog.json must keep.

// Sidebar clusters, in order. A gap is drawn wherever the group changes.
export const GROUPS = ["look", "connectivity", "hardware", "input", "system"]
// Pages drawn mostly by their own view; they need no catalog sections.
export const CUSTOM_PAGES = ["monitors", "network", "devices", "sound", "calendar", "startup", "about"]
// controller.action() ids a catalog section button may run (backend.js op "action").
export const SECTION_ACTIONS = ["reload", "waybar", "update"]
// Live device a section heading may follow (SettingsView resolves it from controller.sound).
export const TITLE_SOURCES = ["sound-output", "sound-input"]

export function navEntries(categories) {
    const entries = categories.filter(category => category.placement !== "footer")
    return entries.map((category, index) =>
        Object.assign({}, category, {gapBefore: index > 0 && category.group !== entries[index - 1].group}))
}

// Groups visible rows (already filtered, in catalog order) into what is drawn. On a
// page: that category's sections in declared order. While searching: every matching
// category in sidebar order, captioned "Page › Section", without footers or buttons.
// Rows naming no declared section form one uncaptioned group after the declared ones,
// so a row is never dropped.
export function pageSections(categories, rows, searching) {
    const out = []
    for (const category of categories) {
        const own = rows.filter(row => row.category === category.id)
        if (!own.length) continue
        const declared = category.sections || []
        for (const section of declared) {
            const members = own.filter(row => row.section === section.id)
            if (!members.length) continue
            out.push({key: category.id + "/" + section.id,
                title: searching ? category.title + " › " + section.title : section.title,
                titleFrom: searching ? "" : section.titleFrom || "",
                footer: searching ? "" : section.footer || "",
                actions: searching ? [] : section.actions || [],
                rows: members})
        }
        const loose = own.filter(row => !declared.some(section => section.id === row.section))
        if (loose.length) out.push({key: category.id + "/", title: searching ? category.title : "", footer: "", actions: [], rows: loose})
    }
    return out
}

// An inverted slider runs from max to min, so dragging right always means what its
// right-hand end label says (Fast); the stored value is untouched. Its own inverse.
export function mirror(row, value) {
    return row.invert ? row.min + row.max - value : value
}

// A row whose dependsOn toggle is off is shown but cannot be edited (blur size without blur).
export function dependencyOff(row, values) {
    return !!row.dependsOn && values[row.dependsOn]?.value === false
}

export function validateCatalog(catalog) {
    const errors = []
    const categories = catalog.categories || []
    const rows = catalog.rows || []
    for (const category of categories) {
        if (!GROUPS.includes(category.group)) errors.push(`${category.id}: unknown group ${category.group}`)
        if (category.placement !== undefined && category.placement !== "footer") errors.push(`${category.id}: unknown placement ${category.placement}`)
        const sections = category.sections || []
        if (!sections.length && !CUSTOM_PAGES.includes(category.id)) errors.push(`${category.id}: no sections`)
        const ids = sections.map(section => section.id)
        if (new Set(ids).size !== ids.length) errors.push(`${category.id}: duplicate section`)
        for (const section of sections) {
            if (!section.title) errors.push(`${category.id}/${section.id}: no title`)
            if (!rows.some(row => row.category === category.id && row.section === section.id))
                errors.push(`${category.id}/${section.id}: empty section`)
            if (section.titleFrom !== undefined && !TITLE_SOURCES.includes(section.titleFrom))
                errors.push(`${category.id}/${section.id}: bad titleFrom ${section.titleFrom}`)
            for (const action of section.actions || [])
                if (!action.label || !SECTION_ACTIONS.includes(action.action))
                    errors.push(`${category.id}/${section.id}: bad action ${action.action}`)
        }
    }
    const runs = categories.map(category => category.group).filter((group, index, all) => index === 0 || group !== all[index - 1])
    for (const group of GROUPS)
        if (runs.filter(run => run === group).length > 1) errors.push(`group ${group} is split`)
    const byId = new Map()
    for (const row of rows) {
        if (byId.has(row.id)) errors.push(`${row.id}: duplicate id`)
        byId.set(row.id, row)
    }
    for (const row of rows) {
        const category = categories.find(candidate => candidate.id === row.category)
        if (!category) { errors.push(`${row.id}: unknown category ${row.category}`); continue }
        if (!row.inView && !(category.sections || []).some(section => section.id === row.section))
            errors.push(`${row.id}: unknown section ${row.section}`)
        if (row.ends !== undefined && !(row.kind === "slider" && Array.isArray(row.ends) && row.ends.length === 2 &&
                row.ends.every(label => typeof label === "string" && label)))
            errors.push(`${row.id}: ends needs two labels on a slider`)
        if (row.invert !== undefined && !(row.kind === "slider" && row.invert === true))
            errors.push(`${row.id}: invert is only true, and only on a slider`)
        if (row.dependsOn !== undefined) {
            const target = byId.get(row.dependsOn)
            if (!target || target.kind !== "toggle" || target.category !== row.category)
                errors.push(`${row.id}: dependsOn must name a toggle on the same page`)
        }
    }
    return errors
}
