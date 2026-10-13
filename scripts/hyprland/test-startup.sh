#!/bin/bash
# Verify optional login applications follow their tracked option files.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/home/.config/options" "$FIXTURE/bin"
printf '%s\n' disabled > "$FIXTURE/home/.config/options/autologin"

cat > "$FIXTURE/bin/protonvpn-app" <<'EOF'
#!/bin/bash
printf '%s\n' started >> "$STARTUP_TEST_EVENTS"
EOF
chmod +x "$FIXTURE/bin/protonvpn-app"

run_startup() {
    HOME="$FIXTURE/home" \
    PATH="$FIXTURE/bin:/usr/bin:/bin" \
    STARTUP_TEST_EVENTS="$FIXTURE/events" \
        bash "$ROOT/scripts/hyprland/startup.sh"
}

printf '%s\n' disabled > "$FIXTURE/home/.config/options/protonvpn"
run_startup
[ ! -e "$FIXTURE/events" ]
echo "ok: disabled Proton VPN option does not launch the app"

printf '%s\n' enabled > "$FIXTURE/home/.config/options/protonvpn"
run_startup
for _ in {1..50}; do
    [ -e "$FIXTURE/events" ] && break
    sleep 0.01
done
[ "$(cat "$FIXTURE/events")" = started ]
echo "ok: enabled Proton VPN option launches the app"

mkdir -p "$FIXTURE/home/.config/scripts/desktop-clock"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/clock-events"\n' "$FIXTURE" \
    > "$FIXTURE/home/.config/scripts/desktop-clock/desktop-clock.sh"
rm -f "$FIXTURE/events"
run_startup
for _ in {1..50}; do
    [ -e "$FIXTURE/clock-events" ] && break
    sleep 0.01
done
[ "$(cat "$FIXTURE/clock-events")" = start ]
echo "ok: login hands the desktop clock to its owner script"
