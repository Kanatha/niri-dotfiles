#!/usr/bin/env bash
# Wi-Fi network picker (nmcli), opened from the control center Wi-Fi tile
# (o / right click). Known networks connect directly; new secured ones ask
# for the password. Picking the connected network disconnects it.
set -euo pipefail

menu() { wofi --dmenu -c "$HOME/.config/wofi/menu-config" --cache-file=/dev/null "$@"; }

if [ "$(nmcli radio wifi)" != enabled ]; then
    nmcli radio wifi on
    sleep 2
fi

notify-send -a Wi-Fi -e -t 1500 "󰤨  Scanning…"
# nmcli -t escapes ':' inside fields as '\:'; split on unescaped colons only.
list=$(nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID dev wifi list --rescan yes |
    sed 's/\\:/\x1f/g' | awk -F: '$4 != "" && !seen[$4]++ {
        gsub("\x1f", ":", $4)
        icon = $2 >= 75 ? "󰤨" : $2 >= 50 ? "󰤥" : $2 >= 25 ? "󰤢" : "󰤟"
        lock = ($3 == "" || $3 == "--") ? "  " : "󰌾 "
        mark = $1 == "*" ? "● " : "  "
        printf "%s\t%s%s %s %s\n", $4, mark, icon, lock, $4
    }')
[ -n "$list" ] || { notify-send -a Wi-Fi "No networks found"; exit 0; }

choice=$(cut -f2 <<< "$list" | menu -p "Wi-Fi") || exit 0
ssid=$(awk -F'\t' -v c="$choice" '$2 == c { print $1; exit }' <<< "$list")
[ -n "$ssid" ] || exit 0

if [[ "$choice" == "● "* ]]; then
    nmcli connection down id "$ssid" >/dev/null && notify-send -a Wi-Fi "󰤭  Disconnected" "$ssid"
    exit 0
fi

if nmcli -t -f NAME connection show | grep -qxF "$ssid"; then
    out=$(nmcli connection up id "$ssid" 2>&1) || { notify-send -a Wi-Fi -u critical "Failed to connect" "$out"; exit 1; }
elif [[ "$choice" == *"󰌾"* ]]; then
    pass=$(menu -p "Password for $ssid" --password < /dev/null) || exit 0
    out=$(nmcli dev wifi connect "$ssid" password "$pass" 2>&1) || { notify-send -a Wi-Fi -u critical "Failed to connect" "$out"; exit 1; }
else
    out=$(nmcli dev wifi connect "$ssid" 2>&1) || { notify-send -a Wi-Fi -u critical "Failed to connect" "$out"; exit 1; }
fi
notify-send -a Wi-Fi "󰤨  Connected" "$ssid"
