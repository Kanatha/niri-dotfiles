#!/usr/bin/env bash
# Regenerates all three keyboard-layout diagrams (qwerty/dvorak/qwertz_si)
# shown by Mod+G. Run this after editing lily58-keymap.yaml.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

for layer in qwerty dvorak qwertz_si; do
    keymap -c nord-draw-config.yaml draw -k lily58/rev1 lily58-keymap.yaml -s "$layer" \
        | rsvg-convert --background-color '#2e3440' -o "$layer.png"
    echo "generated $layer.png"
done
