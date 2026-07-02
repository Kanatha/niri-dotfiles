#!/usr/bin/env bash
# Prints "<index>: <output-name>" for the output this waybar instance is
# running on, e.g. "1: eDP-1". Index is the output's position (1-based)
# among all outputs sorted by name, so it stays stable across restarts.
set -euo pipefail

name="${WAYBAR_OUTPUT_NAME:-?}"

index=$(niri msg -j outputs | jq -r --arg name "$name" 'keys | sort | index($name)')
if [ "$index" = "null" ] || [ -z "$index" ]; then
    echo "$name"
else
    echo "$((index + 1)): $name"
fi
