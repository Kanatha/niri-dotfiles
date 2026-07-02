#!/usr/bin/env bash
# Shows a diagram of the currently active keyboard layout (Programmer
# Dvorak / QWERTY / Slovenian QWERTZ) as it lands on the physical Lily58,
# in a floating image viewer. Images are pre-rendered by keymap-drawer —
# see ~/.config/keymap-drawer/lily58-keymap.yaml to regenerate them.
set -euo pipefail

idx=$(niri msg -j keyboard-layouts | python3 -c "import json,sys; print(json.load(sys.stdin)['current_idx'])")

case "$idx" in
    0) image="dvorak.png" ;;
    1) image="qwerty.png" ;;
    2) image="qwertz_si.png" ;;
    *) exit 1 ;;
esac

imv-wayland "$HOME/.config/keymap-drawer/$image"
