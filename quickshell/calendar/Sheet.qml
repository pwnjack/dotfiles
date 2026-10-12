pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import "model.mjs" as Model

// New event, in the style of a phone's calendar sheet. Every edit goes through the model and back to the
// controller (setDraft), so the shell can load the start day's events.
FocusScope {
    id: sheet
    required property var card
    // The room the card leaves for the sheet. Its top bar stays put; everything under it scrolls.
    property real maxHeight: Infinity
    readonly property var d: card.c.draft
    readonly property var check: d ? Model.validate(d) : ({ ok: false, endBeforeStart: false })
    // The draft's calendar must be one the shell can write to now: a restored draft can name one that is gone.
    readonly property bool calendarOk: !!d && card.c.calendars.some(c => c.writable && c.name === d.calendar)
    // Add needs a title, a sensible span and a calendar to write to.
    readonly property bool ready: !!d && check.ok && calendarOk
    // An event opened for editing; a read-only one (other calendar's, or an invitation) has no Done or Delete.
    readonly property bool editing: !!d && d.mode === "edit"
    readonly property bool readOnly: editing && d.readOnly
    // The start day's other events: an event being edited is the draft on the timeline, not a block under it.
    readonly property var dayEvents: d && card.c.dayFor === d.startDay
        ? card.c.dayEvents.filter(e => !Model.isDraftOf(d, e)) : []
    readonly property var conflicts: d ? Model.clashes(d, dayEvents) : []
    readonly property var allDayOthers: dayEvents.filter(e => e.allDay)
    property string expanded: ""            // "", "startDate", "endDate", "startTime", "endTime", "calendar", "alert"
    property string prompting: ""           // "", "save", "delete": the scope prompt over the sheet
    property int pickYear: 2026             // the month the open date picker shows
    property int pickMonth: 0
    property Item opener: null          // the pill whose picker or menu is open; focus returns to it
    implicitHeight: col.implicitHeight
    // The fields show the draft's text. Typing is the only edit that comes from a field, and it
    // already matches the draft, so this writes only when the draft was replaced under them.
    function syncFields() {
        if (!d) return;
        if (titleField.text !== d.title) titleField.text = d.title;
        if (locationField.text !== d.location) locationField.text = d.location;
    }
    onDChanged: syncFields()
    onVisibleChanged: {
        if (visible && d) { syncFields(); titleField.forceActiveFocus(); }
        if (!visible) { expanded = ""; prompting = ""; }
    }
    onExpandedChanged: {
        if (expanded === "startDate" || expanded === "endDate") {
            opener = expanded === "startDate" ? startDatePill : endDatePill;
            (expanded === "startDate" ? startPicker : endPicker).forceActiveFocus();
            return;
        }
        if (expanded === "calendar" || expanded === "alert") {
            opener = expanded === "calendar" ? calendarPill : alertPill;
            placeMenu(expanded === "calendar" ? calendarMenu : alertMenu, opener);
            return;
        }
        if (expanded === "" && opener) opener.forceActiveFocus();
        opener = null;
    }
    // A menu opens under its pill, right edges aligned, or above it when only that
    // side has room; with room on neither, it takes the roomier side and scrolls.
    // It stays inside the sheet's visible part, and follows its pill while rows above
    // still move (a picker closing as it opens); a wheel or drag over the sheet closes it.
    readonly property bool menuOpen: expanded === "calendar" || expanded === "alert"
    function placeMenu(menu, pill) {
        const gap = card.px(4);
        const viewTop = scroll.mapToItem(sheet, 0, 0).y, viewBottom = viewTop + scroll.height;
        const top = pill.mapToItem(sheet, 0, 0).y;
        // The room either side is measured from the part of the pill that is in view.
        const seenTop = Math.max(viewTop, Math.min(viewBottom, top));
        const seenBottom = Math.max(viewTop, Math.min(viewBottom, top + pill.height));
        const below = viewBottom - seenBottom - gap, aboveRoom = seenTop - gap - viewTop;
        const full = menu.items.length * menu.rowHeight + 2 * menu.pad;
        menu.maxWidth = width;
        menu.above = full > below && (full <= aboveRoom || aboveRoom > below);
        menu.maxHeight = Math.max(menu.rowHeight + 2 * menu.pad, menu.above ? aboveRoom : below);
        // A sheet row's controls end flush with its right margin (SheetRow: 12 px), whatever
        // their width, so the menu lines up there rather than on a measurement taken mid-layout.
        menu.anchorRight = width - card.px(12);
        menu.anchorY = menu.above ? top - gap : top + pill.height + gap;
        // A pill scrolled partly out of view still gets its whole menu on screen.
        menu.bandTop = viewTop;
        menu.bandBottom = viewBottom;
    }
    function replaceMenu() {
        if (expanded === "calendar") placeMenu(calendarMenu, calendarPill);
        else if (expanded === "alert") placeMenu(alertMenu, alertPill);
    }
    Connections { target: inner; function onImplicitHeightChanged() { sheet.replaceMenu(); } }
    onHeightChanged: replaceMenu()
    onWidthChanged: replaceMenu()
    // An open menu or dropdown is closed by a click anywhere outside it; the card asks here first.
    function closeMenu() { if (!menuOpen) return false; expanded = ""; return true; }

    function set(next) { card.c.setDraft(next); }
    // Done (edit) or Add (new). A repeating event asks which occurrences first; a one-off saves at once.
    function done() {
        if (readOnly || prompting !== "" || !ready) return;
        if (!editing) { card.c.add(); return; }
        if (Model.scopeChoices(d).length) { prompting = "save"; return; }
        card.c.save("all");
    }
    // Return saves only with nothing open: an open dropdown or picker takes its own Return,
    // and one that passes it on (a picker before any arrow key) must not add the event.
    function returnPressed() { if (expanded === "") done(); }
    function fmtTime(s) { return Model.formatTime(Model.minutesOf(s), card.c.clock, card.c.locale.amText, card.c.locale.pmText); }
    function fmtDay(key) { return card.c.locale.toString(new Date(Model.dayStart(key) * 1000), "ddd d MMM yyyy"); }
    function stepTime(which, steps) {
        if (which === "start") set(Model.moveStart(d, d.start + steps * 900));
        else set(Model.setEnd(d, d.end + steps * 900));
    }
    // The picker's month is read on its own, so its busy dots do not depend on the card's month.
    function requestPickerMonth() {
        card.c.loadPickerMonth(pickYear + "-" + String(pickMonth + 1).padStart(2, "0"));
    }
    function toggle(which) {
        // A typed time is applied before its field closes, so clicking another pill keeps it.
        const was = expanded;
        if (was === "startTime") startTimeField.commit();
        else if (was === "endTime") endTimeField.commit();
        if (was === which) { expanded = ""; return; }
        if (which === "startDate" || which === "endDate") {
            const key = which === "startDate" ? d.startDay : d.endDay;
            pickYear = Number(key.slice(0, 4));
            pickMonth = Number(key.slice(5, 7)) - 1;
            requestPickerMonth();
        }
        expanded = which;
    }
    function shiftPicker(delta) {
        const m = new Date(pickYear, pickMonth + delta, 1);
        pickYear = m.getFullYear();
        pickMonth = m.getMonth();
        requestPickerMonth();
    }

    // Esc closes whatever is open in the sheet first; with nothing open the card's ladder takes it.
    // An open scope prompt closes first, then an open pill, then the card's ladder takes it.
    Keys.onEscapePressed: event => {
        if (prompting !== "") { prompting = ""; event.accepted = true; }
        else if (expanded !== "") { expanded = ""; event.accepted = true; }
        else event.accepted = false;
    }
    // Return saves from anywhere in the sheet once valid. Pills and time fields take it first.
    Keys.onReturnPressed: event => { returnPressed(); event.accepted = true; }
    Keys.onEnterPressed: event => { returnPressed(); event.accepted = true; }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: sheet.card.px(10)
        visible: !!sheet.d
        RowLayout {
            id: bar
            Layout.fillWidth: true
            Text {
                objectName: "cancelButton"
                text: "Cancel"
                color: sheet.card.c.accent
                font.family: sheet.card.c.monoFont
                font.pixelSize: sheet.card.px(13)
                MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: sheet.card.c.cancelSheet() }
            }
            Text {
                objectName: "sheetTitle"
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: sheet.readOnly ? "Event" : sheet.editing ? "Edit event" : "New event"
                color: sheet.card.c.foreground
                font.family: sheet.card.c.monoFont
                font.pixelSize: sheet.card.px(15)
                font.weight: Font.DemiBold
            }
            Rectangle {
                id: addButton
                objectName: "addButton"
                enabled: sheet.ready
                visible: !sheet.readOnly
                width: addLabel.implicitWidth + sheet.card.px(26)
                height: sheet.card.px(28)
                radius: sheet.card.px(9)
                color: enabled ? sheet.card.c.accent : Qt.rgba(sheet.card.c.foreground.r, sheet.card.c.foreground.g, sheet.card.c.foreground.b, 0.10)
                activeFocusOnTab: true
                Text {
                    id: addLabel
                    objectName: "addLabel"
                    anchors.centerIn: parent
                    text: sheet.editing ? "Done" : "Add"
                    font.weight: Font.Bold
                    font.family: sheet.card.c.monoFont
                    font.pixelSize: sheet.card.px(13)
                    color: addButton.enabled ? sheet.card.c.accentInk : sheet.card.dim
                }
                MouseArea { anchors.fill: parent; enabled: addButton.enabled; cursorShape: addButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: sheet.done() }
            }
        }
        Flickable {
            id: scroll
            objectName: "sheetScroll"
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(inner.implicitHeight, Math.max(0, sheet.maxHeight - bar.height - col.spacing))
            contentHeight: inner.implicitHeight
            clip: true
            // The sheet can scroll under an open menu without the user (a picker closing shrinks
            // it): the menu follows. A wheel or drag by the user lands on the catcher and closes it.
            onContentYChanged: sheet.replaceMenu()
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: inner
                width: scroll.width
                spacing: sheet.card.px(12)
            Text {
                objectName: "readOnlyLine"
                visible: sheet.readOnly
                Layout.fillWidth: true
                text: sheet.d && sheet.d.invitation ? "Invitation · read-only here" : "Read-only calendar"
                color: sheet.card.dim
                wrapMode: Text.Wrap
                font.family: sheet.card.c.monoFont
                font.pixelSize: sheet.card.px(12.5)
            }
            Text {
                objectName: "addError"
                visible: text !== ""
                text: sheet.card.c.addError
                color: "#eaa3a4"
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                font.family: sheet.card.c.monoFont
                font.pixelSize: sheet.card.px(12.5)
            }

            // Group 1: title, location
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: g1.implicitHeight + sheet.card.px(8)
                radius: sheet.card.px(12)
                color: Qt.rgba(sheet.card.c.foreground.r, sheet.card.c.foreground.g, sheet.card.c.foreground.b, 0.06)
                enabled: !sheet.readOnly
                ColumnLayout {
                    id: g1
                    y: sheet.card.px(4)
                    width: parent.width
                    spacing: 0
                    Controls.TextField {
                        id: titleField
                        objectName: "titleField"
                        Layout.fillWidth: true
                        Layout.preferredHeight: sheet.card.px(40)
                        leftPadding: sheet.card.px(12); rightPadding: sheet.card.px(12)
                        topPadding: 0; bottomPadding: 0
                        verticalAlignment: TextInput.AlignVCenter
                        activeFocusOnTab: true
                        enabled: !sheet.readOnly
                        placeholderText: "Title"
                        onTextChanged: if (sheet.d && text !== sheet.d.title) sheet.set(Object.assign({}, sheet.d, { title: text }))
                        Keys.onReturnPressed: event => { sheet.returnPressed(); event.accepted = true; }
                        Keys.onEnterPressed: event => { sheet.returnPressed(); event.accepted = true; }
                        color: sheet.card.c.foreground
                        placeholderTextColor: sheet.card.dim
                        font.family: sheet.card.c.monoFont
                        font.pixelSize: sheet.card.px(13)
                        background: Item {}
                    }
                    Rectangle { Layout.fillWidth: true; Layout.leftMargin: sheet.card.px(12); implicitHeight: 1; color: sheet.card.line }
                    Controls.TextField {
                        id: locationField
                        objectName: "locationField"
                        Layout.fillWidth: true
                        Layout.preferredHeight: sheet.card.px(40)
                        leftPadding: sheet.card.px(12); rightPadding: sheet.card.px(12)
                        topPadding: 0; bottomPadding: 0
                        verticalAlignment: TextInput.AlignVCenter
                        activeFocusOnTab: true
                        enabled: !sheet.readOnly
                        placeholderText: "Location"
                        onTextChanged: if (sheet.d && text !== sheet.d.location) sheet.set(Object.assign({}, sheet.d, { location: text }))
                        Keys.onReturnPressed: event => { sheet.returnPressed(); event.accepted = true; }
                        Keys.onEnterPressed: event => { sheet.returnPressed(); event.accepted = true; }
                        color: sheet.card.c.foreground
                        placeholderTextColor: sheet.card.dim
                        font.family: sheet.card.c.monoFont
                        font.pixelSize: sheet.card.px(13)
                        background: Item {}
                    }
                }
            }

            // Group 2: all day, starts, ends, timeline
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: g2.implicitHeight + sheet.card.px(8)
                radius: sheet.card.px(12)
                color: Qt.rgba(sheet.card.c.foreground.r, sheet.card.c.foreground.g, sheet.card.c.foreground.b, 0.06)
                enabled: !sheet.readOnly
                ColumnLayout {
                    id: g2
                    y: sheet.card.px(4)
                    width: parent.width
                    spacing: 0
                    SheetRow {
                        card: sheet.card
                        label: "All day"
                        Toggle {
                            objectName: "allDaySwitch"
                            card: sheet.card
                            enabled: !sheet.readOnly && !(sheet.d && sheet.d.recurring)
                            checked: !!sheet.d && sheet.d.allDay
                            onToggled: sheet.set(Model.setAllDay(sheet.d, !checked))
                        }
                    }
                    SheetRow {
                        card: sheet.card
                        label: "Starts"
                        Pill {
                            id: startDatePill
                            objectName: "startDate"
                            card: sheet.card
                            enabled: !sheet.readOnly && !(sheet.d && sheet.d.recurring)
                            text: sheet.d ? sheet.fmtDay(sheet.d.startDay) : ""
                            active: sheet.expanded === "startDate"
                            onClicked: sheet.toggle("startDate")
                        }
                        Pill {
                            objectName: "startTime"
                            visible: !!sheet.d && !sheet.d.allDay && sheet.expanded !== "startTime"
                            card: sheet.card
                            enabled: !sheet.readOnly
                            text: sheet.d ? sheet.fmtTime(sheet.d.start) : ""
                            onClicked: sheet.toggle("startTime")
                            onWheelStep: steps => sheet.stepTime("start", steps)
                        }
                        TimeField {
                            id: startTimeField
                            objectName: "startTimeField"
                            visible: sheet.expanded === "startTime"
                            card: sheet.card
                            value: sheet.d ? Model.minutesOf(sheet.d.start) : 0
                            onChosen: minutes => { sheet.set(Model.moveStart(sheet.d, Model.at(sheet.d.startDay, minutes))); sheet.expanded = ""; }
                        }
                    }
                    Reveal {
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        card: sheet.card
                        padding: sheet.card.px(10)
                        open: sheet.expanded === "startDate"
                        MonthGrid {
                            id: startPicker
                            objectName: "startPicker"
                            width: parent.width
                            returnPicksSelected: true
                            enabled: sheet.expanded === "startDate"
                            card: sheet.card
                            peek: false
                            titleOpens: false
                            year: sheet.pickYear
                            month: sheet.pickMonth
                            selected: sheet.d ? sheet.d.startDay : ""
                            onPicked: key => { sheet.set(Model.setStartDay(sheet.d, key)); sheet.expanded = ""; }
                            onPrev: sheet.shiftPicker(-1)
                            onNext: sheet.shiftPicker(1)
                        }
                    }
                    SheetRow {
                        card: sheet.card
                        label: "Ends"
                        Pill {
                            id: endDatePill
                            objectName: "endDate"
                            card: sheet.card
                            enabled: !sheet.readOnly && !(sheet.d && sheet.d.recurring)
                            text: sheet.d ? sheet.fmtDay(sheet.d.endDay) : ""
                            strikeout: sheet.check.endBeforeStart
                            active: sheet.expanded === "endDate"
                            onClicked: sheet.toggle("endDate")
                        }
                        Pill {
                            objectName: "endTime"
                            visible: !!sheet.d && !sheet.d.allDay && sheet.expanded !== "endTime"
                            card: sheet.card
                            enabled: !sheet.readOnly
                            text: sheet.d ? sheet.fmtTime(sheet.d.end) : ""
                            strikeout: sheet.check.endBeforeStart
                            onClicked: sheet.toggle("endTime")
                            onWheelStep: steps => sheet.stepTime("end", steps)
                        }
                        TimeField {
                            id: endTimeField
                            objectName: "endTimeField"
                            visible: sheet.expanded === "endTime"
                            card: sheet.card
                            value: sheet.d ? Model.minutesOf(sheet.d.end) : 0
                            onChosen: minutes => { sheet.set(Model.setEnd(sheet.d, Model.at(sheet.d.endDay, minutes))); sheet.expanded = ""; }
                        }
                    }
                    Reveal {
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        card: sheet.card
                        padding: sheet.card.px(10)
                        open: sheet.expanded === "endDate"
                        MonthGrid {
                            id: endPicker
                            objectName: "endPicker"
                            width: parent.width
                            returnPicksSelected: true
                            enabled: sheet.expanded === "endDate"
                            card: sheet.card
                            peek: false
                            titleOpens: false
                            year: sheet.pickYear
                            month: sheet.pickMonth
                            selected: sheet.d ? sheet.d.endDay : ""
                            onPicked: key => { sheet.set(Model.setEndDay(sheet.d, key)); sheet.expanded = ""; }
                            onPrev: sheet.shiftPicker(-1)
                            onNext: sheet.shiftPicker(1)
                        }
                    }
                    ColumnLayout {
                        visible: !!sheet.d && !sheet.d.allDay
                        Layout.fillWidth: true
                        Layout.margins: sheet.card.px(12)
                        spacing: sheet.card.px(4)
                        Text {
                            text: sheet.d ? sheet.card.c.locale.toString(new Date(Model.dayStart(sheet.d.startDay) * 1000), "dddd d MMMM") : ""
                            color: sheet.card.dim
                            font.family: sheet.card.c.monoFont
                            font.pixelSize: sheet.card.px(12)
                        }
                        Timeline {
                            objectName: "sheetTimeline"
                            Layout.fillWidth: true
                            card: sheet.card
                            day: sheet.d ? sheet.d.startDay : ""
                            events: sheet.dayEvents
                            draft: sheet.d
                            editable: false      // a click here would leave an edit half-made
                            pickable: true
                            onGapClicked: minutes => sheet.set(Model.moveStart(sheet.d, Model.at(sheet.d.startDay, minutes)))
                        }
                        Repeater {
                            model: sheet.conflicts
                            delegate: Text {
                                required property var modelData
                                required property int index
                                objectName: "overlap" + index
                                text: "⚠ Overlaps " + modelData.title + " " + sheet.fmtTime(modelData.startEpoch) + "–" + sheet.fmtTime(modelData.endEpoch)
                                color: "#eaa3a4"
                                font.family: sheet.card.c.monoFont
                                font.pixelSize: sheet.card.px(12.5)
                                // A long title wraps inside the card instead of running past it.
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                wrapMode: Text.WordWrap
                            }
                        }
                        Text {
                            visible: sheet.allDayOthers.length > 0
                            text: "Also that day: " + sheet.allDayOthers.map(e => "● " + e.title).join("  ")
                            color: sheet.card.dim
                            font.family: sheet.card.c.monoFont
                            font.pixelSize: sheet.card.px(12)
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            // Group 3: calendar, alert
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: g3.implicitHeight + sheet.card.px(8)
                radius: sheet.card.px(12)
                color: Qt.rgba(sheet.card.c.foreground.r, sheet.card.c.foreground.g, sheet.card.c.foreground.b, 0.06)
                enabled: !sheet.readOnly
                ColumnLayout {
                    id: g3
                    y: sheet.card.px(4)
                    width: parent.width
                    spacing: 0
                    SheetRow {
                        id: calendarRow
                        card: sheet.card
                        label: "Calendar"
                        Pill {
                            id: calendarPill
                            maxWidth: calendarRow.room
                            objectName: "calendarValue"
                            card: sheet.card
                            enabled: !sheet.readOnly
                            text: sheet.d ? (sheet.calendarOk ? sheet.d.calendar + "  ›" : "No writable calendar") : ""
                            active: sheet.expanded === "calendar"
                            onClicked: sheet.toggle("calendar")
                        }
                    }
                    SheetRow {
                        card: sheet.card
                        label: "Alert"
                        Pill {
                            id: alertPill
                            objectName: "alertPill"
                            card: sheet.card
                            enabled: !sheet.readOnly
                            text: sheet.d ? Model.alertLabel(sheet.d) + "  ›" : ""
                            active: sheet.expanded === "alert"
                            onClicked: sheet.toggle("alert")
                            // Add sits in the top bar, so the chain would wrap past it: Tab from the last field goes to Add.
                            KeyNavigation.tab: addButton
                            // The label without the chevron, for tests and screen readers.
                            Text { objectName: "alertValue"; visible: false; text: sheet.d ? Model.alertLabel(sheet.d) : "" }
                        }
                    }
                }
            }
            Rectangle {
                objectName: "deleteButton"
                visible: sheet.editing && !sheet.readOnly
                Layout.fillWidth: true; implicitHeight: sheet.card.px(36); radius: sheet.card.px(12)
                color: Qt.rgba(sheet.card.c.foreground.r, sheet.card.c.foreground.g, sheet.card.c.foreground.b, 0.06)
                Text { anchors.centerIn: parent; text: "Delete event"; color: "#e0787a"; font.weight: Font.DemiBold
                    font.family: sheet.card.c.monoFont; font.pixelSize: sheet.card.px(13) }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sheet.prompting = "delete" }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: sheet.editing ? "Return saves · Esc cancels" : "Return adds · Esc cancels"
                color: sheet.card.dim
                font.family: sheet.card.c.monoFont
                font.pixelSize: sheet.card.px(12)
            }
            }
        }
    }

    // The dropdowns float over the sheet. A click anywhere else closes the open one
    // and does nothing more, as a menu does on the desktop.
    MouseArea {
        anchors.fill: parent
        anchors.margins: -sheet.card.px(16)      // the card's padding too: the whole card, not just the sheet
        z: 39
        visible: sheet.menuOpen
        onClicked: sheet.expanded = ""
        onWheel: wheel => { sheet.expanded = ""; }
    }
    Menu {
        id: calendarMenu
        objectName: "calendarMenu"
        open: sheet.expanded === "calendar"
        card: sheet.card
        items: sheet.card.c.calendars.filter(c => c.writable).map(c => ({ value: c.name, label: c.name, color: c.color }))
        current: sheet.d ? sheet.d.calendar : ""
        onChosen: value => { sheet.set(Object.assign({}, sheet.d, { calendar: value })); sheet.expanded = ""; }
    }
    Menu {
        id: alertMenu
        objectName: "alertMenu"
        open: sheet.expanded === "alert"
        card: sheet.card
        items: Model.alertItems(sheet.d || {}).map(a => ({ value: a.id, label: a.label }))
        current: sheet.d ? sheet.d.alert : ""
        onChosen: value => { sheet.set(Object.assign({}, sheet.d, { alert: value })); sheet.expanded = ""; }
    }

    // Last child, so it covers the whole sheet while a repeating event asks its scope.
    ScopePrompt {
        objectName: "scopePrompt"
        visible: sheet.prompting !== ""
        card: sheet.card
        question: sheet.prompting === "delete"
            ? (sheet.d && sheet.d.recurring ? "Delete this repeating event?" : "Delete event?")
            : "Save changes to this repeating event?"
        choices: {
            const d = sheet.d || {};
            if (sheet.prompting === "delete") {
                if (!d.recurring) return [{ value: "all", label: "Delete", danger: true }];
                return Model.deleteChoices(d).map(v => ({ value: v, label: v === "one" ? "This event only" : "All events", danger: true }));
            }
            return Model.scopeChoices(d).map(v => ({ value: v, label: v === "one" ? "This event only" : "All events" }));
        }
        onChosen: value => { const what = sheet.prompting; sheet.prompting = "";
            if (what === "delete") sheet.card.c.remove(value); else sheet.card.c.save(value); }
        onCancelled: sheet.prompting = ""
    }
}
