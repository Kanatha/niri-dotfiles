#!/usr/bin/env bash
# SSH into a host in a new terminal, bound to Mod+S. Hosts come from
# ~/.ssh/config (Host entries without wildcards) and ~/.ssh/known_hosts;
# typing user@host that isn't listed works too.
set -euo pipefail

hosts=$(
    {
        [ -r ~/.ssh/config ] && awk 'tolower($1) == "host" { for (i = 2; i <= NF; i++) print $i }' ~/.ssh/config | grep -v '[*?]'
        [ -r ~/.ssh/known_hosts ] && cut -d' ' -f1 ~/.ssh/known_hosts | tr ',' '\n' | grep -v '^|' | sed 's/^\[\(.*\)\]:.*/\1/'
    } 2>/dev/null | sort -u
)

choice=$(printf '%s\n' "$hosts" | sed '/^$/d' | wofi --dmenu -p "SSH host" \
    -c "$HOME/.config/wofi/menu-config" --cache-file=/dev/null) || exit 0
[ -n "$choice" ] || exit 0

setsid -f alacritty --title "ssh $choice" -e ssh "$choice" >/dev/null 2>&1
