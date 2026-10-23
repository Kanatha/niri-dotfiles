#!/usr/bin/env bash
# Jump to any open window across workspaces, bound to Mod+Tab.
# Entries: "<workspace>  <app> — <title>", most recently focused first.
set -euo pipefail

windows=$(niri msg --json windows)
workspaces=$(niri msg --json workspaces)

entries=$(jq -r --argjson ws "$workspaces" '
    ($ws | map({key: (.id | tostring), value: (.name // (.idx | tostring))}) | from_entries) as $names
    | sort_by(-(.focus_timestamp.secs // 0), -(.focus_timestamp.nanos // 0))
    | .[] | "\(.id)\t\($names[(.workspace_id // 0) | tostring] // "-")  \(.app_id // "?") — \(.title // "")"
' <<< "$windows")
[ -n "$entries" ] || exit 0

choice=$(cut -f2- <<< "$entries" | wofi --dmenu -p "Windows" \
    -c "$HOME/.config/wofi/menu-config" --cache-file=/dev/null) || exit 0
id=$(awk -F'\t' -v c="$choice" '$2 == c { print $1; exit }' <<< "$entries")
[ -n "$id" ] && niri msg action focus-window --id "$id"
