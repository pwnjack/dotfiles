#!/usr/bin/env python3
"""Check matugen palettes against the wallpaper gallery's readability gate."""

import argparse
import math
import os
from pathlib import Path
import re
import subprocess
import tempfile


ANSI = ("red", "green", "yellow", "blue", "magenta", "cyan")


def linear_rgb(color):
    if not re.fullmatch(r"#[0-9a-f]{6}", color):
        raise ValueError(f"invalid color {color!r}")
    rgb = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
                 for c in rgb)


def contrast(first, second):
    def luminance(color):
        r, g, b = linear_rgb(color)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b

    low, high = sorted((luminance(first), luminance(second)))
    return (high + 0.05) / (low + 0.05)


def hue_chroma(color):
    """OKLab conversion using the constants from palette.sh's wal_oklch."""
    r, g, b = linear_rgb(color)
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return math.degrees(math.atan2(b, a)) % 360, math.hypot(a, b)


def hue_in(hue, lo, hi):
    return lo <= hue <= hi if lo <= hi else hue >= lo or hue <= hi


def score(colors, roles):
    if len(colors) != 16:
        raise ValueError("expected 16 ANSI slots")
    for color in colors:
        linear_rgb(color)
    surface = colors[0]
    failures = []
    # Score the foreground and background slots consumers actually draw.
    pairs = [("body", colors[7], 7),
             ("muted", colors[8], 3),
             ("accent", roles["primary"], 4.5)]
    pairs.extend((name, colors[index], 3) for index, name in enumerate(ANSI, 1))
    for name, color, minimum in pairs:
        ratio = contrast(color, surface)
        if ratio < minimum:
            failures.append(f"{name} {ratio:.2f}")
    for index, name, lo, hi in ((1, "red", 350, 50), (2, "green", 110, 170)):
        hue, chroma = hue_chroma(colors[index])
        if not hue_in(hue, lo, hi) or chroma < 0.06:
            failures.append(f"{name} not {name} (hue {hue:.1f}, chroma {chroma:.3f})")
    return failures


def score_image(image, config):
    with tempfile.TemporaryDirectory(prefix="score-palette-") as scratch:
        root = Path(scratch)
        # Keep both the generator and matugen away from live user state.
        env = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(config),
                   XDG_CACHE_HOME=str(root / "cache"), XDG_STATE_HOME=str(root / "state"))
        out = root / "palette"
        result = subprocess.run(
            [str(config / "scripts/theming/generate-palette.sh"), str(image), str(out)],
            env=env, capture_output=True, text=True, check=False)
        if result.returncode:
            detail = " ".join(result.stderr.split()) or f"exit {result.returncode}"
            return [f"generation failed: {detail}"]
        colors = (out / "colors").read_text().splitlines()
        roles = dict(line.split("=", 1) for line in (out / "roles").read_text().splitlines())
        return score(colors, roles)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wallpaper_dir", type=Path)
    args = parser.parse_args()
    directory = args.wallpaper_dir.expanduser().resolve()
    if not directory.is_dir():
        parser.error(f"not a directory: {directory}")
    config = Path(__file__).resolve().parents[2]
    images = sorted(path for path in directory.iterdir()
                    if path.is_file() and path.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"})
    if not images:
        print(f"No supported wallpaper images found in {directory}")
        return 1
    failing = 0
    for image in images:
        try:
            failures = score_image(image, config)
        except (OSError, ValueError, KeyError) as error:
            failures = [f"generation failed: {error}"]
        if failures:
            failing += 1
            print(f"{image.name}: {', '.join(failures)}", flush=True)
    print(f"{len(images)} wallpapers, {failing} failing")
    return int(failing > 0)


if __name__ == "__main__":
    raise SystemExit(main())
