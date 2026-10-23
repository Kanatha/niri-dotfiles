#!/usr/bin/env bash
# Pick the default audio output (sink) or input (source) and move every
# running stream over to it. Bound to the waybar pulseaudio module:
# left click = output, right click = input.
set -euo pipefail

case "${1:-output}" in
    output) kind=sink;   streams=sink-inputs;    prompt="Output" ;;
    input)  kind=source; streams=source-outputs; prompt="Input" ;;
    *) echo "usage: $0 [output|input]" >&2; exit 1 ;;
esac

current=$(pactl "get-default-$kind")

# "<name>\t<label>", current device first and marked with ●.
# Monitor sources (loopbacks of outputs) aren't real inputs, so skip them.
devices=$(pactl -f json list "${kind}s" | jq -r --arg cur "$current" '
    map(select(.properties["device.class"] != "monitor"))
    | sort_by(.name != $cur)
    | .[] | "\(.name)\t\(if .name == $cur then "● " else "   " end)\(.description)"')
[ -n "$devices" ] || exit 0

choice=$(cut -f2 <<< "$devices" | wofi --dmenu -p "$prompt" \
    -c "$HOME/.config/wofi/audio-config" --cache-file=/dev/null) || exit 0
[ -z "$choice" ] && exit 0

name=$(awk -F'\t' -v c="$choice" '$2 == c { print $1; exit }' <<< "$devices")
[ -z "$name" ] || [ "$name" = "$current" ] && exit 0

pactl "set-default-$kind" "$name"
pactl list short "$streams" | cut -f1 | while read -r id; do
    pactl "move-${streams%s}" "$id" "$name" 2>/dev/null || true
done
