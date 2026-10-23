#!/usr/bin/env bash
# Emoji / symbol picker, bound to Mod+Semicolon. Types the pick into the
# focused window with wtype (falls back to the clipboard if wtype isn't
# installed) and always copies it too. The list is built once from
# Python's Unicode database: emoji, arrows, math, Greek, shapes, dingbats.
set -euo pipefail

list="${XDG_CACHE_HOME:-$HOME/.cache}/emoji-picker.txt"

if [ ! -s "$list" ]; then
    python3 - "$list" <<'PY'
import sys, unicodedata
ranges = [
    (0x1F300, 0x1FAFF),  # emoji: symbols, pictographs, faces, transport, ...
    (0x2600, 0x27BF),    # misc symbols, dingbats
    (0x2190, 0x21FF),    # arrows
    (0x2200, 0x22FF),    # math operators
    (0x2300, 0x23FF),    # technical
    (0x25A0, 0x25FF),    # geometric shapes
    (0x2B00, 0x2BFF),    # more arrows / shapes
    (0x0391, 0x03C9),    # Greek
    (0x00A1, 0x00BF),    # Latin-1 punctuation and signs
    (0x2010, 0x2044),    # dashes, quotes, bullets
    (0x20A0, 0x20C0),    # currency
]
with open(sys.argv[1], "w") as f:
    for lo, hi in ranges:
        for cp in range(lo, hi + 1):
            name = unicodedata.name(chr(cp), None)
            if name:
                f.write(f"{chr(cp)}  {name.lower()}\n")
PY
fi

choice=$(wofi --dmenu -p "Emoji" -c "$HOME/.config/wofi/menu-config" \
    --cache-file=/dev/null < "$list") || exit 0
char="${choice%%  *}"
[ -n "$char" ] || exit 0

printf '%s' "$char" | wl-copy
if command -v wtype >/dev/null; then
    sleep 0.1  # let wofi's surface go away so the target window has focus
    wtype "$char"
fi
