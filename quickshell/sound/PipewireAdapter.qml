pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Live PipeWire as plain JS objects for model.mjs: `nodes` is a NodeIn[] (the
// shape in model.mjs), rebuilt wholesale on any change and coalesced to one
// rebuild per event-loop turn. Properties and link states exist only for bound
// objects, so every node and every link group is bound; all of it is released
// when the popover exits.
// Links come from Pipewire.linkGroups: PwNodeLinkTracker follows isSink, which
// Quickshell sets on output streams, so it sees only links into them (none).
Scope {
    id: adapter

    readonly property bool ready: Pipewire.ready
    property var nodes: []
    // The actual defaults (what plays now), never the configured preference.
    readonly property int defaultSink: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.id : -1
    readonly property int defaultSource: Pipewire.defaultAudioSource ? Pipewire.defaultAudioSource.id : -1

    readonly property var linkStateNames: {
        const names = {};
        names[PwLinkState.Error] = "error";
        names[PwLinkState.Unlinked] = "unlinked";
        names[PwLinkState.Init] = "init";
        names[PwLinkState.Negotiating] = "negotiating";
        names[PwLinkState.Allocating] = "allocating";
        names[PwLinkState.Paused] = "paused";
        names[PwLinkState.Active] = "active";
        return names;
    }

    function node(id) {
        const all = Pipewire.nodes.values;
        for (let i = 0; i < all.length; i++) if (all[i].id === id) return all[i];
        return null;
    }
    function setDefault(kind, id) {
        const target = node(id);
        if (!target) return;
        if (kind === "output") Pipewire.preferredDefaultAudioSink = target;
        else Pipewire.preferredDefaultAudioSource = target;
    }
    function setVolume(id, volume) {
        const target = node(id);
        if (target && target.audio) target.audio.volume = volume;
    }
    function setMuted(id, muted) {
        const target = node(id);
        if (target && target.audio) target.audio.muted = muted;
    }

    property bool queued: false
    function schedule() {
        if (queued) return;
        queued = true;
        Qt.callLater(rebuild);
    }
    function rebuild() {
        queued = false;
        const list = [];
        for (let i = 0; i < entries.count; i++) {
            const entry = entries.objectAt(i);
            if (entry && entry.value) list.push(entry.value);
        }
        nodes = list;
    }

    PwObjectTracker { objects: Pipewire.nodes.values }
    PwObjectTracker { objects: Pipewire.linkGroups.values }

    Instantiator {
        id: entries
        model: Pipewire.nodes
        onObjectAdded: adapter.schedule()
        onObjectRemoved: adapter.schedule()
        delegate: QtObject {
            required property PwNode modelData
            // Reads every reactive part of the node, so any change re-runs it.
            // PipeWire properties are strings: model.mjs tests the two flags it
            // reads as booleans. isSink means a device sink here, as in the
            // fixtures: Quickshell also sets it on output streams.
            readonly property var value: {
                const n = modelData;
                if (!n.ready || !n.audio) return null;
                const raw = n.properties || {};
                const props = {};
                for (const key in raw) props[key] = raw[key];
                props["node.virtual"] = raw["node.virtual"] === "true";
                props["node.passive"] = raw["node.passive"] === "true";
                const linkStates = [];
                const linkTargets = [];
                const groups = n.isStream ? Pipewire.linkGroups.values : [];
                for (let i = 0; i < groups.length; i++) {
                    const group = groups[i];
                    if (!group.source || group.source.id !== n.id || !group.target) continue;
                    linkStates.push(adapter.linkStateNames[group.state] || "unlinked");
                    linkTargets.push(group.target.id);
                }
                return {
                    id: n.id,
                    name: n.name,
                    description: n.description,
                    isSink: n.isSink && !n.isStream,
                    isStream: n.isStream,
                    props: props,
                    volume: n.audio.volume,
                    muted: n.audio.muted,
                    channels: n.audio.channels.length,
                    linkStates: linkStates,
                    linkTargets: linkTargets,
                };
            }
            onValueChanged: adapter.schedule()
        }
    }
}
