#!/usr/bin/env bash
# Status for custom/control (center of the bar): screen recording, focus
# countdown, caffeine, night light and do-not-disturb indicators plus the
# unread notification count. Clicking it (or Mod+Grave) toggles the control
# center panel in ~/.config/control-center. Refreshed via signal 9 by the
# panel, the ~/.local/bin scripts and the notification logger.
set -euo pipefail

history_file="${XDG_CACHE_HOME:-$HOME/.cache}/mako-notif-history.jsonl"
seen_file="${XDG_CACHE_HOME:-$HOME/.cache}/mako-notif-seen"

unread=0
if [ -s "$history_file" ]; then
    seen=0
    [ -s "$seen_file" ] && seen=$(cat "$seen_file")
    unread=$(jq -s --argjson seen "$seen" '[.[] | select(.time > $seen)] | length' "$history_file")
fi

icons=()
class=()
tooltip="Control center (Super+\`)"

if pgrep -x wf-recorder >/dev/null; then
    icons+=("<span color='#bf616a'>󰑋</span>")
    tooltip+=" · recording"
fi
focus=$("$HOME/.local/bin/focus-mode" status)
if [ "$focus" != off ]; then
    icons+=("󰀠 ${focus}m")
    class+=("focus")
    tooltip+=" · focus ${focus}m left"
fi
if [ "$("$HOME/.local/bin/caffeine" status)" = on ]; then
    icons+=("󰅶")
fi
read -r night _ < <("$HOME/.local/bin/nightlight" status)
if [ "$night" = on ]; then
    icons+=("󰖔")
fi
if makoctl mode | grep -qx do-not-disturb; then
    [ "$focus" = off ] && icons+=("󰂛") && class+=("dnd")
elif [ "$unread" -gt 0 ]; then
    icons+=("󰂚 $unread")
    class+=("has-notifications")
else
    icons+=("󰂚")
fi
tooltip+=" · $unread new"

jq -nc --arg text "${icons[*]}" --arg class "${class[*]:-}" --arg tooltip "$tooltip" \
    '{text: $text, tooltip: $tooltip, class: ($class | split(" ") | map(select(. != "")))}'
