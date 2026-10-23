#!/usr/bin/env bash
# Confirms then runs a power action (logout/reboot/shutdown), triggered
# from waybar's power menu.
set -euo pipefail

action="$1"

case "$action" in
    logout)   label="Log out" ;;
    reboot)   label="Reboot" ;;
    shutdown) label="Shut down" ;;
    *) exit 1 ;;
esac

confirm=$(printf 'No\nYes\n' | wofi --dmenu -p "$label?" \
    -c "$HOME/.config/wofi/notes-config" --cache-file=/dev/null)
[ "$confirm" = "Yes" ] || exit 0

case "$action" in
    logout)   niri msg action quit -s ;;
    reboot)   systemctl reboot ;;
    shutdown) systemctl poweroff ;;
esac
