# Capture bar, recording and locking

Contract (full behaviour, options, lock rules and troubleshooting: [capture.md](../capture.md)):

- `quickshell/capture/shell.qml` is the strip, started by `scripts/hyprland/capture-bar.sh`; `model.mjs` is the pure model. Modes are `screenshot`, `text`, `record`, cycled by `Tab` and `Backtab` in the model; the bar launcher accepts `text` as a mode too. [The strip](../capture.md#the-strip).
- `scripts/capture/record.sh` is the only driver of gpu-screen-recorder; `scripts/hyprland/screenshot.sh` is the only screenshot command; `scripts/hyprland/lock.sh` is the only lock path, and it locks first. [Pieces](../capture.md#pieces), [Recording](../capture.md#recording), [Lock and suspend](../capture.md#lock-and-suspend).
- `scripts/capture/read-text.sh` is the only place that decodes (zbarimg, then tesseract). [Copying text or a QR code](../capture.md#copying-text-or-a-qr-code).
- The strip writes only `options/capture-*`, synchronously (`blockWrites`). [Options](../capture.md#options).
- `scripts/capture/toast.sh` holds the shared saved toast and `open_toast`, the detached Open-only toast `read-text.sh` uses for a copied link. [Recording](../capture.md#recording).

## Test timing overrides

Recording subprocess tests can override `CAPTURE_START_WAIT` (0.5 s),
`CAPTURE_TICK_WAIT` and `CAPTURE_COUNTDOWN_WAIT` (1 s each), and
`CAPTURE_STOP_POLL_WAIT` and `CAPTURE_DISCARD_POLL_WAIT` (0.1 s each).
These defaults preserve production timing; the countdown still uses its
wall-clock deadline. The existing `CAPTURE_STOP_WAIT` controls the stop loop's
budget (10 s with the default poll interval). Tests shorten polling and fake
save delays, and wait for stop markers to be consumed before counting toasts.
