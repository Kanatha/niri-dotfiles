#!/usr/bin/env bash
# Bluetooth device picker (bluetoothctl), opened from the control center
# Bluetooth tile (o / right click). Lists paired devices: picking one
# connects it, or disconnects it if it's already connected. New devices are
# paired through the full manager (last entry).
set -euo pipefail

if bluetoothctl show | grep -q 'Powered: no'; then
    bluetoothctl power on >/dev/null
    sleep 1
fi

list=$(bluetoothctl devices Paired | while read -r _ mac name; do
    if bluetoothctl info "$mac" | grep -q 'Connected: yes'; then
        printf '%s\t● 󰂱 %s\n' "$mac" "$name"
    else
        printf '%s\t  󰂯 %s\n' "$mac" "$name"
    fi
done)
manager="  󰂳 Pair a new device…"

choice=$(printf '%s\n%s\n' "$(cut -f2 <<< "$list")" "$manager" | sed '/^$/d' |
    wofi --dmenu -p "Bluetooth" -c "$HOME/.config/wofi/menu-config" --cache-file=/dev/null) || exit 0

if [ "$choice" = "$manager" ]; then
    setsid -f blueman-manager >/dev/null 2>&1
    exit 0
fi
mac=$(awk -F'\t' -v c="$choice" '$2 == c { print $1; exit }' <<< "$list")
[ -n "$mac" ] || exit 0
name=$(bluetoothctl devices Paired | awk -v m="$mac" '$2 == m { sub(/^Device [^ ]+ /, ""); print; exit }')

if [[ "$choice" == "● "* ]]; then
    bluetoothctl disconnect "$mac" >/dev/null && notify-send -a Bluetooth "󰂲  Disconnected" "$name"
else
    notify-send -a Bluetooth -e -t 2000 "󰂱  Connecting…" "$name"
    if bluetoothctl connect "$mac" >/dev/null 2>&1; then
        notify-send -a Bluetooth "󰂱  Connected" "$name"
    else
        notify-send -a Bluetooth -u critical "Couldn't connect" "$name"
    fi
fi
