#!/usr/bin/env bash
# Restarts waybar after every resume from suspend. On wake niri briefly
# re-adds eDP-1 before settling on HDMI-A-1, and waybar 0.12 races on
# that hotplug and ends up with two bars stacked on the same output.
# Run by waybar-resume.service.
set -euo pipefail

# logind emits PrepareForSleep(true) before suspend and (false) after resume.
gdbus monitor --system --dest org.freedesktop.login1 \
    --object-path /org/freedesktop/login1 |
while read -r line; do
    case "$line" in
        *PrepareForSleep*false*)
            # Let the outputs settle before waybar re-enumerates them.
            sleep 2
            systemctl --user restart waybar.service
            ;;
    esac
done
