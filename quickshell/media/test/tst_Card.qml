import QtQuick
import QtTest
import ".."

Item {
    id: host
    width: 1600
    height: 900

    // Stand-ins with Quickshell's MprisPlayer property names. Objects, as
    // the real players are: a chip knows its player by identity.
    Component {
        id: standIn
        QtObject {
            property string dbusName: "org.mpris.MediaPlayer2.spotify"
            property string identity: "Spotify"
            property string trackTitle: "Night Drive"
            property string trackArtist: "Example Artist"
            property string trackAlbum: "Example Album"
            property string trackArtUrl: ""
            property bool isPlaying: true
            property int uniqueId: 1
            property real length: 220
            property bool lengthSupported: true
            property bool canSeek: true
            property bool canTogglePlaying: true
            property bool canGoNext: true
            property bool canGoPrevious: true
        }
    }
    function music(overrides) { return standIn.createObject(host, overrides || {}); }
    function browser() {
        return standIn.createObject(host, {
            dbusName: "org.mpris.MediaPlayer2.firefox.instance_1_2810", identity: "Mozilla zen",
            trackTitle: "A video", trackArtist: "A channel", trackAlbum: "",
            isPlaying: false, length: 134, canGoNext: false, canGoPrevious: false
        });
    }

    QtObject {
        id: controller
        property color background: "#05090c"
        property color foreground: "#cfddde"
        property color accent: "#6097a1"
        property string monoFont: "monospace"
        property real uiScale: 1
        property bool opened: true
        property var player: null
        property var players: []
        property real position: 0
        // Every call the card makes, as "name" or "seek:<whole seconds>".
        property var calls: []
        property var shown: null
        function close() { calls.push("close"); }
        function toggle() { calls.push("toggle"); }
        function next() { calls.push("next"); }
        function previous() { calls.push("previous"); }
        function seek(seconds) { calls.push("seek:" + Math.round(seconds)); }
        function show(next) { shown = next; player = next; calls.push("show"); }
    }
    Card {
        id: card
        controller: controller
        focus: true
    }
    TestCase {
        name: "Card"
        when: windowShown

        function part(name) {
            const item = findChild(card, name);
            verify(item !== null, name + " exists");
            return item;
        }
        function play(player, others) {
            controller.player = player;
            controller.players = others || [player];
            // Rows come and go with the player; let the column settle
            // before anything is measured or clicked.
            waitForRendering(card, 500);
        }
        function init() {
            play(host.music());
            controller.position = 72;
            controller.calls = [];
            controller.shown = null;
            card.forceActiveFocus();
        }

        function test_track() {
            compare(card.width, 372, "the weather card's width, at 1:1");
            compare(part("title").text, "Night Drive");
            compare(part("artist").text, "Example Artist");
            compare(part("album").text, "Example Album");
            compare(part("elapsed").text, "1:12");
            compare(part("length").text, "3:40");
            const track = part("played").parent;
            fuzzyCompare(part("played").width, track.width * 72 / 220, 0.5);
            verify(part("thumb").visible);
            verify(!part("chips").visible, "one player: no chips");
            verify(!part("title").truncated && !part("artist").truncated);
        }
        function test_markupIsShownLiterally() {
            play(host.music({ trackTitle: "<b>Tom & Jerry</b>", trackArtist: "<i>Cat</i>" }));
            for (const name of ["title", "artist", "album"]) compare(part(name).textFormat, Text.PlainText, name);
            compare(part("title").text, "<b>Tom & Jerry</b>");
            // Read as markup the tags would not take width; as text they do.
            verify(part("title").implicitWidth > part("artist").implicitWidth);
        }
        function test_emptyRowsAreAbsent() {
            play(host.music({ trackArtist: "", trackAlbum: "" }));
            verify(!part("artist").visible);
            verify(!part("album").visible);
            verify(part("title").visible);
        }
        function test_longTitleStaysInside() {
            play(host.music({ trackTitle: "A very long title that goes on and on well past the width of any card there is, twice over" }));
            const title = part("title");
            verify(title.truncated);
            verify(title.lineCount <= 2);
            verify(title.mapToItem(card, title.width, 0).x <= card.width - 18);
        }
        function test_placeholderWithoutArt() {
            verify(part("placeholder").parent.visible, "no URL: the placeholder");
            // A file that is not there fails to load: still the placeholder.
            play(host.music({ trackArtUrl: "file:///nonexistent/cover.png" }));
            compare(String(part("art").source), "file:///nonexistent/cover.png");
            tryCompare(part("art"), "status", Image.Error);
            verify(part("placeholder").parent.visible);
            // A scheme the model refuses never reaches the image.
            play(host.music({ trackArtUrl: "http://images.example/cover.jpg" }));
            compare(String(part("art").source), "");
        }
        function test_noSeekRowWithoutALength() {
            const tall = card.height;
            play(host.music({ length: 0 }));
            verify(!part("seekRow").visible);
            verify(card.height < tall, "the card closes up");
        }
        function test_releaseSeeks() {
            const area = part("seekArea");
            mouseClick(area, area.width / 2, area.height / 2);
            compare(controller.calls, ["seek:110"]);
        }
        function test_dragSeeksOnce() {
            const area = part("seekArea"), y = area.height / 2;
            mousePress(area, area.width * 0.25, y);
            mouseMove(area, area.width * 0.5, y);
            compare(controller.calls, [], "nothing is sent while dragging");
            compare(part("elapsed").text, "1:50", "the time follows the thumb");
            fuzzyCompare(part("played").width, area.width * 0.5, 0.5);
            mouseMove(area, area.width * 0.75, y);
            mouseRelease(area, area.width * 0.75, y);
            compare(controller.calls, ["seek:165"]);
            compare(part("elapsed").text, "1:12", "released: the player's position again");
        }
        function test_dragPastTheEndStops() {
            const area = part("seekArea"), y = area.height / 2;
            mousePress(area, area.width * 0.5, y);
            mouseMove(area, area.width + 200, y);
            mouseRelease(area, area.width + 200, y);
            compare(controller.calls, ["seek:220"]);
        }
        function test_aDragIntoTheNextTrackSeeksNothing() {
            const area = part("seekArea"), y = area.height / 2;
            mousePress(area, area.width * 0.9, y);
            controller.player.trackTitle = "The Next Song";
            mouseMove(area, area.width * 0.95, y);
            compare(part("elapsed").text, "1:12", "the thumb is let go");
            mouseRelease(area, area.width * 0.95, y);
            compare(controller.calls, []);
            // The next press is a new gesture.
            mouseClick(area, area.width / 2, y);
            compare(controller.calls, ["seek:110"]);
        }
        function test_controlsAreNamedButtons() {
            const names = { previous: "Previous", toggle: "Pause", next: "Next" };
            for (const name in names) {
                compare(part(name).Accessible.name, names[name]);
                compare(part(name).Accessible.role, Accessible.Button);
            }
            controller.player.isPlaying = false;
            compare(part("toggle").Accessible.name, "Play");
            const spotify = controller.player, zen = host.browser();
            play(spotify, [spotify, zen]);
            const list = part("chipList");
            compare(list.itemAt(1).Accessible.name, "Mozilla zen");
            compare(list.itemAt(1).Accessible.role, Accessible.RadioButton);
            verify(list.itemAt(0).Accessible.checked && !list.itemAt(1).Accessible.checked);
        }
        function test_aDisabledControlIgnoresAScreenReadersPress() {
            // Qt runs an accessible action on a disabled item; each one checks.
            play(host.browser());
            part("next").Accessible.pressAction();
            compare(controller.calls, [], "the button itself is off");
            card.enabled = false;
            part("toggle").Accessible.pressAction();
            part("seekRow").Accessible.increaseAction();
            compare(controller.calls, [], "and so is everything under a disabled card");
            card.enabled = true;
            part("toggle").Accessible.pressAction();
            compare(controller.calls, ["toggle"]);
        }
        function test_theSeekRowIsASlider() {
            const row = part("seekRow"), area = part("seekArea"), y = area.height / 2;
            compare(row.Accessible.role, Accessible.Slider);
            compare(row.Accessible.name, "Seek, 1:12");
            row.Accessible.increaseAction();
            row.Accessible.decreaseAction();
            compare(controller.calls, ["seek:77", "seek:67"]);
            mousePress(area, area.width * 0.5, y);
            compare(row.Accessible.name, "Seek, 1:50", "the time under a held thumb");
            mouseRelease(area, area.width * 0.5, y);
            play(host.music({ canSeek: false }));
            verify(row.Accessible.ignored, "nothing to move: no slider");
        }
        function test_aPlayerThatCannotSeek() {
            play(host.music({ canSeek: false }));
            const area = part("seekArea");
            verify(part("seekRow").visible, "the row still shows the time");
            verify(!part("thumb").visible);
            mouseClick(area, area.width / 2, area.height / 2);
            keyClick(Qt.Key_Right);
            compare(controller.calls, []);
        }
        function test_transport() {
            for (const name of ["previous", "toggle", "next"]) mouseClick(part(name));
            compare(controller.calls, ["previous", "toggle", "next"]);
        }
        function test_whatAPlayerCannotDoIsOff() {
            play(host.browser());
            mouseClick(part("previous"));
            mouseClick(part("next"));
            compare(controller.calls, []);
            verify(part("previous").opacity < 1 && part("next").opacity < 1);
            verify(!part("previous").activeFocusOnTab, "and Tab passes it by");
            mouseClick(part("toggle"));
            compare(controller.calls, ["toggle"]);
        }
        function test_toggleGlyphFollowsThePlayer() {
            const playing = part("toggle").glyph;
            play(host.music({ isPlaying: false }));
            verify(part("toggle").glyph !== playing);
        }
        function test_chips() {
            const spotify = host.music(), zen = host.browser();
            play(spotify, [spotify, zen]);
            const list = part("chipList");
            verify(part("chips").visible);
            compare(list.count, 2);
            compare(findChild(list.itemAt(0), "chipLabel").text, "Spotify");
            compare(findChild(list.itemAt(1), "chipLabel").text, "Mozilla zen");
            compare(String(findChild(list.itemAt(0), "chipLabel").color), String(card.accent), "the shown player's chip");
            mouseClick(list.itemAt(1));
            compare(controller.calls, ["show"]);
            compare(controller.shown, zen);
        }
        function test_aChosenChipKeepsTheFocus() {
            const spotify = host.music(), zen = host.browser();
            play(spotify, [spotify, zen]);
            const chip = part("chipList").itemAt(1);
            chip.forceActiveFocus();
            keyClick(Qt.Key_Return);
            compare(controller.player, zen);
            compare(part("title").text, "A video");
            compare(part("chipList").itemAt(1), chip);
            verify(chip.activeFocus, "the next Tab starts from the chosen chip");
            compare(String(findChild(chip, "chipLabel").color), String(card.accent), "and it is the marked one now");
            compare(String(findChild(part("chipList").itemAt(0), "chipLabel").color), String(card.dim));
        }
        function test_chipsOutliveATick() {
            const spotify = host.music(), zen = host.browser();
            play(spotify, [spotify, zen]);
            const chip = part("chipList").itemAt(1);
            chip.forceActiveFocus();
            controller.position = 73;
            compare(part("chipList").itemAt(1), chip);
            verify(chip.activeFocus, "a new position leaves the focus on its chip");
            keyClick(Qt.Key_Return);
            compare(controller.shown, zen);
        }
        function test_keys() {
            keyClick(Qt.Key_Space);
            keyClick(Qt.Key_Left);
            keyClick(Qt.Key_Right);
            keyClick(Qt.Key_Escape);
            compare(controller.calls, ["toggle", "seek:67", "seek:77", "close"]);
        }
        function test_tabReachesTheButtons() {
            keyClick(Qt.Key_Tab);
            verify(part("previous").activeFocus);
            keyClick(Qt.Key_Return);
            // Space is play or pause wherever the focus is.
            keyClick(Qt.Key_Space);
            compare(controller.calls, ["previous", "toggle"]);
        }
        function test_stepsStopAtTheEnds() {
            controller.position = 2;
            keyClick(Qt.Key_Left);
            controller.position = 218;
            keyClick(Qt.Key_Right);
            compare(controller.calls, ["seek:0", "seek:220"]);
        }
        function test_noPlayer() {
            controller.player = null;
            controller.players = [];
            compare(part("title").text, "");
            verify(!part("seekRow").visible);
            keyClick(Qt.Key_Space);
            compare(controller.calls, [], "nothing to play");
        }
    }
}
