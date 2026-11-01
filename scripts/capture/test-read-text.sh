#!/bin/bash
#
# Tests for scripts/capture/read-text.sh, run as a subprocess the way
# screenshot.sh runs it. zbarimg, tesseract, wl-copy, notify-send and xdg-open
# are fakes from scripts/capture/fakes/; nothing reads a real image, touches the
# real clipboard or posts a real toast.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READ="$TEST_DIR/read-text.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

export FAKE_LOG="$TMP/log" XDG_RUNTIME_DIR="$TMP/run"
mkdir -p "$FAKE_LOG" "$XDG_RUNTIME_DIR" "$TMP/sys"
# The only real tools the script may find; a fake left out of a case's bin
# directory is then a command that is not installed.
for tool in mktemp rm cat; do ln -s "$(command -v "$tool")" "$TMP/sys/$tool"; done
BASH_BIN=$(command -v bash)

# bin_without <name>... -- a PATH directory holding every fake but those named.
# Never deleted before the suite ends: a detached Open toast runs after the script.
bin_without() {
    local dir="$TMP/bin.$$.$RANDOM" fake
    mkdir -p "$dir"
    for fake in "$TEST_DIR"/fakes/*; do
        [[ " $* " == *" ${fake##*/} "* ]] || ln -s "$fake" "$dir/${fake##*/}"
    done
    echo "$dir"
}

# run [-n name]... -- feed $INPUT (default: some PNG bytes) to read-text.sh.
run() {
    local omit=() bin
    while [ "${1-}" = -n ]; do omit+=("$2"); shift 2; done
    rm -rf "$FAKE_LOG"; mkdir -p "$FAKE_LOG"
    bin=$(bin_without "${omit[@]}")
    printf '%s' "${INPUT-PNG}" | PATH="$bin:$TMP/sys" "$BASH_BIN" "$READ"
    RC=$?
}
clip() { cat "$FAKE_LOG/clip" 2>/dev/null; }
toasts() { cat "$FAKE_LOG/notify" 2>/dev/null; }
# The detached Open toast logs from a background shell.
wait_for() {
    local _
    for _ in $(seq 100); do [ -e "$1" ] && return 0; /usr/bin/sleep 0.05; done
    return 1
}
leftovers() { find "$XDG_RUNTIME_DIR" -mindepth 1 | wc -l; }
unset ZBAR_OUT TESS_OUT TESS_NO_ITA NOTIFY_CHOICE WLCOPY_FAIL

# --- Empty input ---------------------------------------------------------
INPUT='' run
assert_eq "$RC" 0 "empty input exits 0"
assert_eq "$(toasts)" "" "empty input posts no toast"
assert_eq "$(clip)" "" "empty input copies nothing"
if [ -e "$FAKE_LOG/zbar" ]; then fail "empty input decodes nothing"; else pass "empty input decodes nothing"; fi
assert_eq "$(leftovers)" 0 "empty input leaves no temp file"

# --- A code: a URL ------------------------------------------------------
ZBAR_OUT='https://example.com/a?b=1&c=2' NOTIFY_CHOICE=open run
assert_eq "$RC" 0 "a QR code exits 0"
assert_eq "$(clip)" "https://example.com/a?b=1&c=2" "the URL is copied, with no trailing newline"
assert_contains "$(toasts)" "Code copied" "the code toast"
assert_contains "$(toasts)" "-a|Capture|" "toasts come from Capture"
assert_contains "$(toasts)" "-A|open=Open" "a URL toast offers Open"
assert_contains "$(toasts)" "https://example.com/a?b=1&amp;c=2" "the body is markup-safe"
if wait_for "$FAKE_LOG/xdg-open"; then
    assert_eq "$(cat "$FAKE_LOG/xdg-open")" "https://example.com/a?b=1&c=2" "Open opens the URL"
else
    fail "Open opens the URL"
fi
if [ -e "$FAKE_LOG/tesseract" ]; then fail "a QR code skips OCR"; else pass "a QR code skips OCR"; fi
assert_eq "$(leftovers)" 0 "a QR code leaves no temp file"

# --- A code: not a URL --------------------------------------------------
ZBAR_OUT='WIFI:S:home;T:WPA;P:secret;;' run
assert_eq "$(clip)" "WIFI:S:home;T:WPA;P:secret;;" "a non-URL payload is copied"
assert_contains "$(toasts)" "Code copied" "a non-URL code toast"
case "$(toasts)" in *"open=Open"*) fail "a non-URL toast has no Open" ;; *) pass "a non-URL toast has no Open" ;; esac
ZBAR_OUT='see https://example.com' run
case "$(toasts)" in *"open=Open"*) fail "text around a URL has no Open" ;; *) pass "text around a URL has no Open" ;; esac

# --- Long and multi-line payloads ----------------------------------------
long=$(printf 'x%.0s' $(seq 120))
ZBAR_OUT="$long" run
assert_eq "$(clip)" "$long" "a long payload is copied whole"
body=$(toasts); body=${body##*|}
assert_eq "${#body}" 80 "the body is cut to 80 characters"
ZBAR_OUT=$'first\nsecond line' run
assert_eq "$(clip)" $'first\nsecond line' "a multi-line payload stays whole"
assert_contains "$(toasts)" "|first" "the body is the first line"
case "$(toasts)" in *second*) fail "the body is only the first line" ;; *) pass "the body is only the first line" ;; esac
ZBAR_OUT='-rf --not-an-option' run
assert_contains "$(toasts)" "--|Code copied|-rf --not-an-option" "a body starting with a dash is not an option"

# --- Payload text that looks like zbarimg's own output -----------------
# Payloads come from --raw, so a line inside one that starts "QR-Code:" is
# content, not a second symbol, and its prefix survives.
ZBAR_OUT=$'first\nQR-Code:second' run
assert_eq "$(clip)" $'first\nQR-Code:second' "a TYPE:-looking line inside a payload is kept"
assert_contains "$(cat "$FAKE_LOG/zbar")" "--raw " "zbarimg is asked for raw payloads"

# --- Several symbols -----------------------------------------------------
ZBAR_OUT=$'5901234123457\ntwo' run
assert_eq "$(clip)" $'5901234123457\ntwo' "several symbols are copied one per line"
ZBAR_OUT=$'https://a.example\nhttps://b.example' run
case "$(toasts)" in *"open=Open"*) fail "two URLs have no Open" ;; *) pass "two URLs have no Open" ;; esac

# --- The clipboard fails ---------------------------------------------------
WLCOPY_FAIL=1 ZBAR_OUT='abc' run
assert_contains "$(toasts)" "Could not copy to the clipboard" "a failed copy of a code says so"
case "$(toasts)" in *"Code copied"*) fail "a failed copy claims no success" ;; *) pass "a failed copy claims no success" ;; esac
assert_eq "$RC" 0 "a failed copy exits 0"
WLCOPY_FAIL=1 TESS_OUT='words' run
assert_contains "$(toasts)" "Could not copy to the clipboard" "a failed copy of OCR text says so"
case "$(toasts)" in *"Text copied"*) fail "a failed OCR copy claims no success" ;; *) pass "a failed OCR copy claims no success" ;; esac
TESS_OUT='words' run -n wl-copy
assert_contains "$(toasts)" "Could not copy to the clipboard" "no wl-copy says so"
case "$(toasts)" in *"Text copied"*) fail "no wl-copy claims no success" ;; *) pass "no wl-copy claims no success" ;; esac

# --- OCR -----------------------------------------------------------------
TESS_OUT=$'Hello world\nsecond line   ' run
assert_eq "$(clip)" $'Hello world\nsecond line' "OCR text is copied, trailing whitespace and form feed stripped"
assert_contains "$(toasts)" "|Text copied|Hello world" "the OCR toast shows the first line"
case "$(toasts)" in *"second line"*) fail "the OCR body is only the first line" ;; *) pass "the OCR body is only the first line" ;; esac
assert_eq "$(cat "$FAKE_LOG/tesseract")" "$(sed -n 's/ present$//p' "$FAKE_LOG/zbar" | sed 's/^-q --raw //') - -l eng+ita" "tesseract reads the same image, English and Italian"
assert_eq "$(wc -l < "$FAKE_LOG/tesseract")" 1 "both languages present: one tesseract run"
assert_contains "$(cat "$FAKE_LOG/zbar")" "-q " "zbarimg runs quietly"
assert_eq "$(leftovers)" 0 "OCR leaves no temp file"
TESS_OUT='<b>&' run
assert_contains "$(toasts)" "&lt;b&gt;&amp;" "OCR text is markup-safe"
ZBAR_OUT='' TESS_OUT='  ' run
assert_contains "$(toasts)" "No text found" "whitespace only is no text"
assert_eq "$(clip)" "" "no text copies nothing"
assert_eq "$RC" 0 "no text exits 0"
TESS_OUT='' run
assert_contains "$(toasts)" "No text found" "empty OCR is no text"

# --- Missing Italian data ------------------------------------------------
TESS_NO_ITA=1 TESS_OUT='Ciao' run
assert_eq "$(clip)" "Ciao" "a missing ita file falls back to English"
assert_eq "$(sed -n 2p "$FAKE_LOG/tesseract" | sed 's/^.* - //')" "-l eng" "the second run asks for English only"
assert_contains "$(toasts)" "Text copied" "the fallback still toasts"

# --- Missing tools -------------------------------------------------------
TESS_OUT='from ocr' run -n zbarimg
assert_eq "$(clip)" "from ocr" "no zbarimg: OCR still runs"
assert_contains "$(toasts)" "Text copied" "no zbarimg: the OCR toast"
ZBAR_OUT='abc' run -n tesseract
assert_eq "$(clip)" "abc" "no tesseract: a QR code still works"
run -n tesseract
assert_contains "$(toasts)" "Text recognition needs tesseract" "no tesseract and no code: say so"
assert_eq "$RC" 0 "no tesseract exits 0"
assert_eq "$(clip)" "" "no tesseract copies nothing"
run -n tesseract -n zbarimg
assert_contains "$(toasts)" "Text recognition needs tesseract" "neither tool: say so"
TESS_OUT='quiet' run -n notify-send
assert_eq "$(clip)" "quiet" "no notify-send: the copy still happens"
assert_eq "$RC" 0 "no notify-send exits 0"
ZBAR_OUT='https://example.com' run -n notify-send
assert_eq "$RC" 0 "no notify-send with a URL exits 0"

# --- Temp file location --------------------------------------------------
ZBAR_OUT='x' run
assert_contains "$(cat "$FAKE_LOG/zbar")" " $XDG_RUNTIME_DIR/read-text." "the image goes under XDG_RUNTIME_DIR"
assert_contains "$(cat "$FAKE_LOG/zbar")" " present" "the image holds the input while it is read"
mkdir -p "$TMP/tmpdir"
XDG_RUNTIME_DIR='' TMPDIR="$TMP/tmpdir" ZBAR_OUT='x' run
assert_contains "$(cat "$FAKE_LOG/zbar")" " $TMP/tmpdir/read-text." "without XDG_RUNTIME_DIR it falls back to the temp directory"
assert_eq "$(find "$TMP/tmpdir" -mindepth 1 | wc -l)" 0 "the fallback temp file is removed too"
assert_eq "$(stat -c %a "$(sed -n 's/^-q --raw \(.*\) present$/\1/p' "$FAKE_LOG/zbar")" 2>/dev/null || echo gone)" gone "the temp file is gone after the run"

test_summary read-text
