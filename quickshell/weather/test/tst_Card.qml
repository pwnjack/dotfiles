import QtQuick
import QtTest
import ".."

Item {
    id: host
    width: 1600
    height: 900

    // A forecast in forecast.sh's shape: hours from 21:00 at UTC+1, seven
    // days from that day's midnight, read four minutes after it was fetched.
    readonly property int firstHour: 1795118400
    readonly property int firstDay: 1795042800
    function sample() {
        const hours = [], days = [];
        for (let i = 0; i < 48; i++) hours.push(i);
        for (let d = 0; d < 7; d++) days.push(d);
        return {
            location: "52.52,13.41", place: "Berlin, Germany", fetchedAt: firstHour + 3300, utc_offset_seconds: 3600,
            current: { time: firstHour + 2700, temperature_2m: 8.4, apparent_temperature: 6.2, weather_code: 61, is_day: 0 },
            hourly: {
                time: hours.map(i => firstHour + 3600 * i),
                temperature_2m: hours.map(i => 9 - i * 0.1),
                weather_code: hours.map(i => 3),
                is_day: hours.map(i => 0)
            },
            daily: {
                time: days.map(d => firstDay + 86400 * d),
                weather_code: [61, 3, 0, 2, 71, 95, 45],
                temperature_2m_max: [10, 12, 14, 9, 8, 11, 13],
                temperature_2m_min: [4, 5, 6, -10, 0, 3, 5],
                precipitation_probability_max: [100, 20, 0, 35, 80, 60, 5],
                sunrise: days.map(d => firstDay + 86400 * d + 27240),
                sunset: days.map(d => firstDay + 86400 * d + 58020)
            }
        };
    }

    QtObject {
        id: controller
        property color background: "#05090c"
        property color foreground: "#cfddde"
        property color accent: "#6097a1"
        property string monoFont: "monospace"
        property real uiScale: 1
        property bool opened: true
        property var locale: Qt.locale("en_US")
        property string clockMode: "24h"
        property var forecast: null
        property string phase: "ready"
        property string reason: ""
        property double clock: host.firstHour + 3300 + 240
        property int closes: 0
        function close() { closes += 1; }
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
        function init() {
            controller.forecast = host.sample();
            controller.phase = "ready";
            controller.reason = "";
            controller.clockMode = "24h";
            controller.clock = host.firstHour + 3300 + 240;
            controller.closes = 0;
            card.forceActiveFocus();
            // The frame eases to a new height; let it land before measuring.
            wait(400);
        }

        function test_forecast() {
            compare(card.width, 372, "the update card's width, at 1:1");
            compare(part("title").text, "Light rain");
            compare(part("place").text, "Berlin, Germany");
            compare(part("detail").text, "feels like 6°");
            compare(part("temp").text, "8°");
            compare(part("slots").count, 8);
            verify(part("hours").visible);
            compare(part("days").count, 7);
            compare(part("sun").text, "Sunrise 07:34 · Sunset 16:07");
            compare(part("note").text, "Updated 4 min ago");
            // As text: a Text stores 8-bit channels, the card's own colour does not.
            compare(String(part("note").color), String(card.dim), "the age is quiet");
            // Sun times and the age share one line when they fit.
            compare(part("note").y, part("sun").y);
            verify(!part("title").truncated && !part("place").truncated && !part("detail").truncated);
        }
        function test_rows() {
            const days = part("days");
            for (let i = 0; i < days.count; i++) {
                const row = days.itemAt(i), track = findChild(row, "track"), range = findChild(row, "range"), dot = findChild(row, "dot");
                verify(range.x >= 0 && range.x + range.width <= track.width + 0.5, "row " + i + ": the bar stays on its track");
                compare(dot.visible, i === 0, "row " + i + ": only today has the dot");
                // -10° is the widest low: it must clear the rain figure before it.
                for (const child of row.children)
                    if (child.text !== undefined) verify(child.implicitWidth <= child.width + 0.5, "row " + i + ": '" + child.text + "' fits its column");
            }
            const today = days.itemAt(0), track = findChild(today, "track"), dot = findChild(today, "dot");
            verify(dot.x >= 0 && dot.x + dot.width <= track.width, "the dot is whole inside the track");
            // Warmer now than any day's high: the dot stops at the track's end.
            const hot = host.sample();
            hot.current.temperature_2m = 40;
            controller.forecast = hot;
            const end = findChild(days.itemAt(0), "dot"), rail = findChild(days.itemAt(0), "track");
            compare(end.x + end.width, rail.width, "the dot stops at the end of the track");
            controller.forecast = host.sample();
            compare(findChild(days.itemAt(0), "rain").text, "100%");
            compare(findChild(days.itemAt(1), "rain").text, "", "20% is not worth a figure");
        }
        function test_updatingBehindACopy() {
            controller.phase = "updating";
            compare(part("note").text, "Updating…");
            compare(part("days").count, 7);
        }
        function test_offlineWithACopy() {
            controller.phase = "failed";
            controller.reason = "No connection to Open-Meteo.";
            const note = part("note"), sun = part("sun");
            compare(note.text, "Offline · updated 4 min ago");
            compare(String(note.color), String(card.warn), "the offline note is amber");
            compare(part("title").text, "Light rain", "the copy is still shown");
            compare(part("days").count, 7);
            // Too long to share the sun times' line: it drops below, whole.
            verify(note.y > sun.y, "the note takes its own line");
            verify(note.x >= 0, "and is not cut on the left");
        }
        function test_loading() {
            controller.forecast = null;
            controller.phase = "updating";
            compare(part("title").text, "Weather");
            compare(part("detail").text, "Loading the forecast…");
            verify(!part("place").visible);
            compare(part("temp").text, "");
            compare(part("days").count, 0);
            verify(!part("hours").visible);
            verify(!part("note").parent.visible, "no footer");
            tryVerify(() => card.height < 90, 1000, "the card is the header alone");
        }
        function test_failedWithNothing() {
            controller.forecast = null;
            controller.phase = "failed";
            controller.reason = "The bar has no location yet.";
            compare(part("title").text, "No forecast");
            compare(part("detail").text, "The bar has no location yet.");
            compare(part("days").count, 0);
            verify(!part("hours").visible);
            verify(!part("detail").truncated);
        }
        function test_twelveHourClock() {
            controller.clockMode = "12h";
            compare(part("sun").text, "Sunrise 7:34 AM · Sunset 4:07 PM");
            const slots = part("slots");
            compare(findChild(slots.itemAt(1), "label").text, "12 AM");
            for (let i = 0; i < slots.count; i++) {
                const label = findChild(slots.itemAt(i), "label");
                verify(label.implicitWidth <= slots.itemAt(i).width, "'" + label.text + "' fits its slot");
            }
        }
        function test_weekdaysFollowTheLocale() {
            compare(part("days").itemAt(1).day.label, "Fri");
            controller.locale = Qt.locale("it_IT");
            compare(part("days").itemAt(0).day.label, "Today");
            compare(part("days").itemAt(1).day.label, "ven");
            controller.locale = Qt.locale("en_US");
        }
        // A name too long with its country is shown as the city alone, whole.
        function test_countryGivesWay() {
            const far = host.sample();
            far.place = "Berlin, Federal Republic of Germany";
            controller.forecast = far;
            const place = part("place"), detail = part("detail");
            compare(place.text, "Berlin");
            verify(!place.truncated && !detail.truncated);
            // The same line beside a two-digit temperature, as in the card's own font:
            // 28 characters must still fit.
            const near = host.sample();
            near.place = "Rome, Italy";
            near.current.temperature_2m = 15.4;
            near.current.apparent_temperature = 16.2;
            controller.forecast = near;
            compare(part("temp").text, "15°");
            compare(detail.text, "feels like 16°");
            compare(place.text, "Rome, Italy");
            verify(!place.truncated && !detail.truncated);
        }
        // A long city is cut so that how it feels stays whole, inside the header.
        function test_longPlace() {
            const far = host.sample();
            far.place = "Llanfairpwllgwyngyllgogerychwyrndrobwll, Wales";
            far.current.temperature_2m = -10.4;
            controller.forecast = far;
            const place = part("place"), detail = part("detail"), temp = part("temp");
            // The row places its children a frame after their widths change.
            wait(50);
            verify(place.truncated, "the name is cut");
            verify(!detail.truncated, "the feeling is whole");
            const end = detail.mapToItem(card, detail.width, 0).x, start = temp.mapToItem(card, 0, 0).x;
            verify(end <= start, "and ends before the temperature");
        }
        function test_escapeCloses() {
            keyClick(Qt.Key_Escape);
            compare(controller.closes, 1);
        }
    }
}
