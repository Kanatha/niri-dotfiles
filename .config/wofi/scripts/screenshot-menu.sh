#!/usr/bin/env bash
# Screenshot / screen recording menu, bound to Mod+Shift+S. Plain
# screenshots use niri's own tools (saved to screenshot-path in
# niri/config.kdl and copied to the clipboard); "annotate" opens swappy;
# recordings go to ~/Videos/Recordings via wf-recorder. While a recording
# runs, the waybar pill shows a red dot and this menu offers "Stop".
set -euo pipefail

rec_dir="$HOME/Videos/Recordings"
rec_file="${XDG_RUNTIME_DIR:-/tmp}/recording-path"
# Must match the "signal" set on custom/control in waybar/config.jsonc.
waybar_signal="RTMIN+9"

focused_output() {
    niri msg --json focused-output | jq -r '.name'
}

record() { # [wf-recorder args...]
    if ! command -v wf-recorder >/dev/null; then
        notify-send -a Screenshot -u critical "wf-recorder is not installed" "sudo apt install wf-recorder"
        exit 1
    fi
    mkdir -p "$rec_dir"
    local file
    file="$rec_dir/Recording from $(date '+%Y-%m-%d %H-%M-%S').mp4"
    echo "$file" > "$rec_file"
    setsid -f wf-recorder "$@" -f "$file" >/dev/null 2>&1
    sleep 0.3
    pkill -"$waybar_signal" waybar 2>/dev/null || true
}

if pgrep -x wf-recorder >/dev/null; then
    entries="󰓛  Stop recording"
else
    entries="󰩭  Region
󰏫  Region → annotate
󰍹  Screen
󰏫  Screen → annotate
󰖯  Window
󰑋  Record region
󰑋  Record screen
󰑋  Record screen with audio
󰉋  Open screenshots folder"
fi

choice=$(wofi --dmenu -p "Capture" -c "$HOME/.config/wofi/menu-config" \
    --cache-file=/dev/null <<< "$entries") || exit 0

case "$choice" in
    *"Stop recording")
        pkill -INT -x wf-recorder || true
        while pgrep -x wf-recorder >/dev/null; do sleep 0.1; done
        pkill -"$waybar_signal" waybar 2>/dev/null || true
        file=$(cat "$rec_file" 2>/dev/null || true)
        action=$(notify-send -a Screenshot -i video-x-generic -A open=Open \
            "󰑋  Recording saved" "${file##*/}") || true
        [ "$action" = open ] && xdg-open "$file"
        ;;
    *"Region → annotate")
        region=$(slurp) || exit 0
        grim -g "$region" - | swappy -f -
        ;;
    *"Screen → annotate")
        grim -o "$(focused_output)" - | swappy -f -
        ;;
    *"Region")  niri msg action screenshot ;;
    *"Screen")  niri msg action screenshot-screen ;;
    *"Window")  niri msg action screenshot-window ;;
    *"Record region")
        region=$(slurp) || exit 0
        record -g "$region"
        ;;
    *"Record screen")  record -o "$(focused_output)" ;;
    *"Record screen with audio")  record -o "$(focused_output)" --audio ;;
    *"Open screenshots folder")  xdg-open "$HOME/Pictures/Screenshots" ;;
esac
