import QtQuick
import QtTest
import ".."

Item {
    id: host
    width: 1200
    height: 900

    // The controller contract (Popover.qml's header), faked: functions record
    // their calls, and the few that move the view also change its state.
    QtObject {
        id: controller
        property color background: "#05090c"
        property color foreground: "#cfddde"
        property color accent: "#6097a1"
        property color accentInk: "#05090c"
        property string monoFont: "monospace"
        property real uiScale: 1
        property bool ready: true
        property string tab: "devices"
        property string picker: ""
        property var output: null
        property var input: null
        property var outputs: ({ shown: [], hidden: [] })
        property var inputs: ({ shown: [], hidden: [] })
        property var apps: []
        property var targets: []
        property string status: ""
        property bool pinsKnown: true
        property real meter: 0.38
        property var calls: []
        function record(call) { calls = calls.concat([call]); }
        function setTab(t) { record(["setTab", t]); tab = t; }
        function openPicker(kind) { record(["openPicker", kind]); picker = kind; }
        function closePicker() { record(["closePicker"]); picker = ""; }
        function choose(kind, key) { record(["choose", kind, key]); }
        function setVolume(key, value) { record(["setVolume", key, value]); }
        function setMuted(key, muted) { record(["setMuted", key, muted]); }
        function route(appKey, targetName) { record(["route", appKey, targetName]); }
        function openSettings() { record(["openSettings"]); }
        function openAdvanced() { record(["openAdvanced"]); }
        function close() { record(["close"]); }
    }

    // DeviceView, AppView and route target shapes from model.mjs.
    function headset() {
        return { key: "alsa_output.usb-Logitech_G533", name: "alsa_output.usb-Logitech_G533",
            label: "G533 Wireless Headset Dongle", volume: 0.64, muted: false, battery: 72, current: true, virtual: false };
    }
    function speakers() {
        return { key: "alsa_output.pci-speakers", name: "alsa_output.pci-speakers", label: "Speakers",
            volume: 0.5, muted: false, battery: null, current: false, virtual: false };
    }
    function monitor() {
        return { key: "alsa_output.pci-hdmi", name: "alsa_output.pci-hdmi", label: "ROG PG279Q",
            volume: 1, muted: false, battery: null, current: false, virtual: false };
    }
    function mic() {
        return { key: "alsa_input.usb-Logitech_G533", name: "alsa_input.usb-Logitech_G533", label: "G533 Mic",
            volume: 0.8, muted: false, battery: null, current: true, virtual: false };
    }
    // An AppView is keyed by its stream's object.serial.
    function app(serial, name, volume) {
        return { key: String(serial), serial: serial, name: name, icon: "", initials: name.slice(0, 2).toUpperCase(),
            volume: volume, muted: false, route: { label: "Default", pinned: false, target: "" }, tag: "", pending: false };
    }
    function targets() {
        return [
            { key: "alsa_output.usb-Logitech_G533", name: "alsa_output.usb-Logitech_G533", serial: 61,
                label: "G533 Wireless Headset Dongle", virtual: false, tag: "" },
            { key: "alsa_output.pci-speakers", name: "alsa_output.pci-speakers", serial: 62,
                label: "Speakers", virtual: false, tag: "" },
            { key: "effect_input.virtual_surround", name: "effect_input.virtual_surround", serial: 63,
                label: "Surround 7.1", virtual: true, tag: "7.1" },
        ];
    }

    Popover {
        id: popover
        controller: controller
        x: 40
        y: 20
        focus: true
    }

    TestCase {
        name: "Sound"
        function renderFrame(item) { item.Window.window.update(); verify(waitForRendering(item)); }
        when: windowShown

        function initTestCase() {
            popover.appear();
        }
        function init() {
            failOnWarning(/.?/);
            controller.ready = true;
            controller.tab = "devices";
            controller.picker = "";
            controller.output = headset();
            controller.input = mic();
            controller.outputs = { shown: [headset(), speakers()], hidden: [monitor()] };
            controller.inputs = { shown: [mic()], hidden: [] };
            controller.apps = [app(81, "Firefox", 1), app(92, "World of Warcraft", 0.85)];
            controller.targets = targets();
            controller.status = "";
            controller.pinsKnown = true;
            controller.calls = [];
            popover.forceActiveFocus();
            // The tab fade and the card's height glide finish before any click.
            settle();
            tryCompare(findChild(popover, "picker"), "shownFraction", 0);
            // A commit from the previous test is held until echoed or for 1 s.
            tryVerify(() => !findChild(popover, "outputSlider").holding && !findChild(popover, "inputSlider").holding, 1500);
        }
        function cleanup() {
            if (popover.openMenu) popover.openMenu.close();
            tryVerify(() => popover.openMenu === null);
        }
        function called(name) {
            return controller.calls.filter(call => call[0] === name);
        }
        function settle() {
            renderFrame(popover);
            wait(400);
        }
        function appRow(key) {
            const rows = findChild(popover, "appRows");
            for (let i = 0; i < rows.count; i++) if (rows.itemAt(i).app.key === key) return rows.itemAt(i);
            return null;
        }
        function openRouteMenu(key) {
            controller.tab = "apps";
            settle();
            mouseClick(findChild(appRow(key), "routeLabel"));
            tryVerify(() => popover.openMenu !== null && popover.openMenu.opened);
            return popover.openMenu;
        }

        function test_opens_on_devices() {
            verify(findChild(popover, "tabDevices").checked);
            verify(!findChild(popover, "tabApps").checked);
            compare(findChild(popover, "outputLabel").text, "G533 Wireless Headset Dongle");
            const battery = findChild(popover, "outputBattery");
            verify(battery.visible);
            compare(battery.text, "72 %");
            compare(findChild(popover, "appsBadge").text, "2");
            verify(!findChild(popover, "inputBattery").visible);
        }

        function test_picker_and_back() {
            mouseClick(findChild(popover, "outputChevron"));
            compare(called("openPicker"), [["openPicker", "output"]]);
            const picker = findChild(popover, "picker");
            tryCompare(picker, "shownFraction", 1);
            compare(findChild(picker, "pickerTitle").text, "Output");
            const rows = findChild(picker, "pickerRows");
            compare(rows.count, 2);
            const more = findChild(picker, "showHidden");
            verify(more.visible);
            compare(more.text, "Show 1 hidden");
            const hidden = findChild(picker, "hiddenRows");
            verify(!hidden.itemAt(0).visible);
            mouseClick(more);
            renderFrame(popover);
            const row = hidden.itemAt(0);
            verify(row.visible);
            verify(row.opacity < 1);
            mouseClick(row);
            compare(called("choose"), [["choose", "output", "alsa_output.pci-hdmi"]]);
            keyClick(Qt.Key_Escape);
            compare(called("closePicker").length, 1);
            compare(called("close").length, 0);
            tryCompare(picker, "shownFraction", 0);
            keyClick(Qt.Key_Escape);
            compare(called("close").length, 1);
        }

        function test_not_ready() {
            controller.ready = false;
            controller.output = null;
            controller.input = null;
            renderFrame(popover);
            compare(findChild(popover, "outputLabel").text, "Sound server not running");
            compare(findChild(popover, "inputLabel").text, "Sound server not running");
            verify(!findChild(popover, "outputSlider").visible);
            verify(!findChild(popover, "inputSlider").visible);
        }

        function test_meter_follows_tab() {
            verify(popover.meterActive);
            controller.tab = "apps";
            verify(!popover.meterActive);
            controller.tab = "devices";
            controller.picker = "input";
            verify(!popover.meterActive);
        }

        function test_route_menu() {
            const menu = openRouteMenu("81");
            const entries = findChild(menu.contentItem, "menuEntries");
            const labels = [];
            for (let i = 0; i < entries.count; i++) labels.push(entries.itemAt(i).text);
            compare(labels, ["Default (follows Devices)", "G533 Wireless Headset Dongle", "Speakers", "Surround 7.1"]);
            verify(entries.itemAt(0).checked);
            renderFrame(popover);
            mouseClick(entries.itemAt(3));
            compare(called("route"), [["route", "81", "effect_input.virtual_surround"]]);
            tryVerify(() => popover.openMenu === null);
        }

        function test_route_menu_keeps_hidden_pin() {
            const pinned = app(81, "Firefox", 1);
            pinned.route = { label: "ROG PG279Q", pinned: true, target: "alsa_output.pci-hdmi" };
            controller.apps = [pinned, app(92, "World of Warcraft", 0.85)];
            const menu = openRouteMenu("81");
            const entries = findChild(menu.contentItem, "menuEntries");
            const labels = [];
            for (let i = 0; i < entries.count; i++) labels.push(entries.itemAt(i).text);
            compare(labels, ["Default (follows Devices)", "G533 Wireless Headset Dongle", "Speakers", "ROG PG279Q", "Surround 7.1"]);
            verify(!entries.itemAt(0).checked);
            verify(entries.itemAt(3).checked);
            keyClick(Qt.Key_Escape);
            tryVerify(() => popover.openMenu === null);
            compare(called("close").length, 0);
        }

        function test_status_line() {
            controller.tab = "apps";
            controller.status = "Could not move Firefox to Speakers";
            settle();
            const line = findChild(popover, "statusLine");
            verify(line.visible);
            compare(line.text, "Could not move Firefox to Speakers");
            const tabs = findChild(popover, "tabBar");
            const top = line.mapToItem(popover, 0, 0).y;
            verify(top >= tabs.mapToItem(popover, 0, tabs.height).y);
            verify(top + line.height <= appRow("81").mapToItem(popover, 0, 0).y);
            controller.tab = "devices";
            settle();
            verify(!line.visible);
        }

        function test_default_vanishes() {
            controller.output = null;
            controller.outputs = { shown: [speakers()], hidden: [monitor()] };
            renderFrame(popover);
            compare(findChild(popover, "outputLabel").text, "No output");
            verify(!findChild(popover, "outputSlider").visible);
            mouseClick(findChild(popover, "outputChevron"));
            compare(called("openPicker"), [["openPicker", "output"]]);
            const picker = findChild(popover, "picker");
            tryCompare(picker, "shownFraction", 1);
            const rows = findChild(picker, "pickerRows");
            compare(rows.count, 1);
            compare(rows.itemAt(0).device.label, "Speakers");
            verify(!rows.itemAt(0).checked);
            compare(findChild(picker, "showHidden").text, "Show 1 hidden");
        }

        function test_stream_ends_with_menu_open() {
            openRouteMenu("81");
            controller.apps = [app(92, "World of Warcraft", 0.85)];
            tryVerify(() => popover.openMenu === null);
            renderFrame(popover);
            compare(findChild(popover, "appRows").count, 1);
            compare(called("route"), []);
        }

        function test_slider_ignores_echo_while_pressed() {
            const slider = findChild(popover, "outputSlider");
            const app81 = appRow("81");
            const track = findChild(slider, "track");
            const at = fraction => slider.mapFromItem(track, track.width * fraction, track.height / 2);
            const start = at(0.3);
            mousePress(slider, start.x, start.y);
            const pressedAt = slider.level;
            verify(Math.abs(pressedAt - 0.3) < 0.03, "pressed at " + pressedAt);
            const moved = at(0.4);
            mouseMove(slider, moved.x, moved.y);
            const dragged = slider.level;
            verify(Math.abs(dragged - 0.4) < 0.03, "dragged to " + dragged);
            // Task 6 rebuilds every array and object on each PipeWire change.
            const echo = headset();
            echo.volume = 0.9;
            controller.output = echo;
            // A stream starting in the same change: a plain array model would rebuild every row.
            controller.apps = [app(81, "Firefox", 0.2), app(92, "World of Warcraft", 0.3), app(93, "mpv", 0.4)];
            renderFrame(popover);
            compare(slider.level, dragged);
            compare(findChild(slider, "percent").text, Math.round(dragged * 100) + " %");
            compare(called("setVolume"), []);
            mouseRelease(slider, moved.x, moved.y);
            compare(called("setVolume"), [["setVolume", "alsa_output.usb-Logitech_G533", dragged]]);
            // Released, it shows the commit until the controller reports one,
            // then follows the controller again.
            compare(slider.level, dragged);
            tryCompare(slider, "level", 0.9, 1500);
            // The app rows were updated in place, not rebuilt.
            controller.tab = "apps";
            settle();
            verify(appRow("81") === app81);
            compare(app81.app.volume, 0.2);
        }

        function test_app_slider_survives_replacement() {
            controller.tab = "apps";
            settle();
            const row = appRow("92");
            const slider = findChild(row, "appSlider");
            const track = findChild(slider, "track");
            const start = slider.mapFromItem(track, track.width * 0.5, track.height / 2);
            mousePress(slider, start.x, start.y);
            const held = slider.level;
            controller.apps = [app(81, "Firefox", 1), app(92, "World of Warcraft", 0.1), app(93, "mpv", 0.4)];
            renderFrame(popover);
            verify(appRow("92") === row);
            compare(slider.level, held);
            mouseRelease(slider, start.x, start.y);
            compare(called("setVolume"), [["setVolume", "92", held]]);
            compare(findChild(popover, "appsBadge").text, "3");
        }

        function test_app_slider_release_after_id_reuse_commits_nothing() {
            controller.tab = "apps";
            settle();
            const slider = findChild(appRow("92"), "appSlider");
            const track = findChild(slider, "track");
            const at = popover.mapFromItem(track, track.width * 0.3, track.height / 2);
            mousePress(popover, at.x, at.y);
            // World of Warcraft's stream ends and a new one takes its object
            // id: same name and place in the list, but another serial.
            controller.apps = [app(81, "Firefox", 1), app(97, "World of Warcraft", 0.85)];
            renderFrame(popover);
            verify(appRow("92") === null);
            verify(appRow("97") !== null);
            mouseRelease(popover, at.x, at.y);
            compare(called("setVolume"), []);
        }

        function test_wheel_during_drag_counts_from_the_drag() {
            const slider = findChild(popover, "outputSlider");
            const track = findChild(slider, "track");
            const at = slider.mapFromItem(track, track.width * 0.3, track.height / 2);
            mousePress(slider, at.x, at.y);
            const dragged = slider.level;
            verify(Math.abs(dragged - 0.64) > 0.1, "the drag is away from the backend value");
            mouseWheel(slider, at.x, at.y, 0, 120);
            const expected = Math.round((dragged + 0.01) * 100) / 100;
            compare(called("setVolume"), [["setVolume", "alsa_output.usb-Logitech_G533", expected]]);
            compare(slider.level, expected);
            mouseRelease(slider, at.x, at.y);
        }

        function test_wheel_steps_one_percent() {
            const slider = findChild(popover, "outputSlider");
            mouseWheel(slider, slider.width / 2, slider.height / 2, 0, 120);
            compare(called("setVolume"), [["setVolume", "alsa_output.usb-Logitech_G533", 0.65]]);
            // Before the echo arrives, the next notch counts from the last commit.
            mouseWheel(slider, slider.width / 2, slider.height / 2, 0, 120);
            compare(called("setVolume")[1], ["setVolume", "alsa_output.usb-Logitech_G533", 0.66]);
            const echo = headset();
            echo.volume = 0.66;
            controller.output = echo;
            mouseWheel(slider, slider.width / 2, slider.height / 2, 0, -120);
            compare(called("setVolume")[2], ["setVolume", "alsa_output.usb-Logitech_G533", 0.65]);
            // Half notches (touchpads) add up to one step.
            mouseWheel(slider, slider.width / 2, slider.height / 2, 0, 60);
            compare(called("setVolume").length, 3);
            mouseWheel(slider, slider.width / 2, slider.height / 2, 0, 60);
            compare(called("setVolume")[3], ["setVolume", "alsa_output.usb-Logitech_G533", 0.66]);
        }

        function test_wheel_down_from_over_range_stays_in_range() {
            const loud = headset();
            loud.volume = 1.2;
            controller.output = loud;
            const hot = mic();
            hot.volume = 1.6;
            controller.input = hot;
            renderFrame(popover);
            const output = findChild(popover, "outputSlider");
            mouseWheel(output, output.width / 2, output.height / 2, 0, -120);
            const input = findChild(popover, "inputSlider");
            mouseWheel(input, input.width / 2, input.height / 2, 0, -120);
            const sets = called("setVolume");
            compare(sets.length, 2);
            compare(sets[0][1], "alsa_output.usb-Logitech_G533");
            verify(sets[0][2] <= 1.0, "output committed " + sets[0][2]);
            compare(sets[1][1], "alsa_input.usb-Logitech_G533");
            verify(sets[1][2] <= 1.5, "input committed " + sets[1][2]);
        }

        function test_release_after_default_changes_commits_nothing() {
            const slider = findChild(popover, "outputSlider");
            const track = findChild(slider, "track");
            const at = slider.mapFromItem(track, track.width * 0.3, track.height / 2);
            mousePress(slider, at.x, at.y);
            const next = speakers();
            next.current = true;
            controller.output = next;
            renderFrame(popover);
            mouseRelease(slider, at.x, at.y);
            compare(called("setVolume").filter(call => call[1] === "alsa_output.pci-speakers"), []);
            // The app rows hold the same rule: a row whose stream ended commits nothing.
            controller.tab = "apps";
            settle();
            const appSlider = findChild(appRow("92"), "appSlider");
            const appTrack = findChild(appSlider, "track");
            const appAt = popover.mapFromItem(appTrack, appTrack.width * 0.3, appTrack.height / 2);
            mousePress(popover, appAt.x, appAt.y);
            controller.apps = [app(81, "Firefox", 1)];
            // The row is gone: release where it was.
            mouseRelease(popover, appAt.x, appAt.y);
            compare(called("setVolume").filter(call => call[1] !== "92" && call[1] !== "alsa_output.usb-Logitech_G533"), []);
            compare(called("setVolume").filter(call => call[1] === ""), []);
        }

        function test_virtual_default_is_labelled() {
            const surround = { key: "effect_input.virtual_surround", name: "effect_input.virtual_surround",
                label: "Surround 7.1", volume: 1, muted: false, battery: null, current: true, virtual: true };
            controller.output = surround;
            controller.outputs = { shown: [surround, speakers()], hidden: [] };
            renderFrame(popover);
            const chip = findChild(popover, "outputVirtual");
            verify(chip.visible);
            compare(chip.text, "Virtual");
            verify(!findChild(popover, "inputVirtual").visible);
            controller.openPicker("output");
            const picker = findChild(popover, "picker");
            tryCompare(picker, "shownFraction", 1);
            const rows = findChild(picker, "pickerRows");
            const marked = findChild(rows.itemAt(0), "virtualChip");
            verify(marked.visible);
            compare(marked.text, "Virtual");
            verify(!findChild(rows.itemAt(1), "virtualChip").visible);
        }

        function test_unknown_pins_check_nothing() {
            controller.pinsKnown = false;
            const menu = openRouteMenu("81");
            const entries = findChild(menu.contentItem, "menuEntries");
            compare(entries.itemAt(0).text, "Default (follows Devices)");
            for (let i = 0; i < entries.count; i++) verify(!entries.itemAt(i).checked, entries.itemAt(i).text);
            // Menus still route, Default included.
            renderFrame(popover);
            mouseClick(entries.itemAt(0));
            compare(called("route"), [["route", "81", "default"]]);
        }

        function test_mute_toggles() {
            mouseClick(findChild(popover, "outputMute"));
            compare(called("setMuted"), [["setMuted", "alsa_output.usb-Logitech_G533", true]]);
        }

        function test_over_range_volume() {
            const loud = headset();
            loud.volume = 1.2;
            controller.output = loud;
            renderFrame(popover);
            const slider = findChild(popover, "outputSlider");
            compare(findChild(slider, "percent").text, "120 %");
            const track = findChild(slider, "track");
            const handle = findChild(slider, "handle");
            compare(handle.x + handle.width / 2, track.x + track.width);
            const end = slider.mapFromItem(track, track.width + 4, track.height / 2);
            mousePress(slider, end.x, end.y);
            mouseRelease(slider, end.x, end.y);
            const sets = called("setVolume");
            compare(sets.length, 1);
            verify(sets[0][2] <= 1.0, "committed " + sets[0][2]);
            // The input card allows software gain up to 150 %.
            compare(findChild(popover, "inputSlider").max, 1.5);
        }

        function test_long_names_elide() {
            const name = "Extremely Long Device Name That Keeps Going And Going Forever";
            verify(name.length >= 60);
            const loud = headset();
            loud.label = name;
            controller.output = loud;
            controller.apps = [app(81, name, 1), app(92, "World of Warcraft", 0.85)];
            settle();
            compare(popover.width, 340);
            const label = findChild(popover, "outputLabel");
            verify(label.width <= findChild(popover, "outputCard").width, "output label " + label.width);
            controller.tab = "apps";
            settle();
            const row = appRow("81");
            const appName = findChild(row, "appName");
            verify(appName.width <= row.width, "app name " + appName.width);
            const route = findChild(row, "routeLabel");
            verify(appName.mapToItem(row, appName.width, 0).x <= route.mapToItem(row, 0, 0).x);
            verify(route.mapToItem(row, route.width, 0).x <= row.width);
        }

        function test_many_apps_scroll() {
            const many = [];
            for (let i = 0; i < 12; i++) many.push(app(200 + i, "App " + i, 0.5));
            controller.apps = many;
            controller.tab = "apps";
            settle();
            verify(popover.height <= 560, "card height " + popover.height);
            const list = findChild(popover, "appsList");
            verify(list instanceof Flickable);
            verify(list.contentHeight > list.height);
            compare(findChild(popover, "appsBadge").text, "12");
        }

        function test_nothing_playing() {
            controller.apps = [];
            controller.tab = "apps";
            settle();
            const empty = findChild(popover, "appsEmpty");
            verify(empty.visible);
            compare(empty.text, "Nothing is playing");
            verify(!findChild(popover, "appsBadge").visible);
        }

        function test_header_actions() {
            mouseClick(findChild(popover, "settingsButton"));
            compare(called("openSettings").length, 1);
            mouseClick(findChild(popover, "moreButton"));
            tryVerify(() => popover.openMenu !== null && popover.openMenu.opened);
            const advanced = popover.openMenu.contentItem;
            compare(advanced.objectName, "advancedEntry");
            compare(advanced.text, "Advanced…");
            renderFrame(popover);
            mouseClick(advanced);
            compare(called("openAdvanced").length, 1);
            tryVerify(() => popover.openMenu === null);
        }

        function test_tab_click() {
            mouseClick(findChild(popover, "tabApps"));
            compare(called("setTab"), [["setTab", "apps"]]);
            verify(findChild(popover, "tabApps").checked);
        }
    }
}
