#!/usr/bin/env bash
# Attach to a tmux session in a new terminal, or create one, bound to
# Mod+Shift+Return. Typing a name that doesn't exist creates that session.
set -euo pipefail

sessions=$(tmux list-sessions -F '#{session_name}  (#{session_windows} windows#{?session_attached, · attached,})' 2>/dev/null || true)

choice=$(printf '%s\n' "$sessions" | sed '/^$/d' | wofi --dmenu -p "tmux session (type a new name to create)" \
    -c "$HOME/.config/wofi/menu-config" --cache-file=/dev/null) || exit 0
name="${choice%%  (*}"
[ -n "$name" ] || exit 0

setsid -f alacritty -e tmux new-session -A -s "$name" >/dev/null 2>&1
