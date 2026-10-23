#!/usr/bin/env bash
# Open a project, bound to Mod+Shift+P: a tmux session named after it with
# windows for nvim, a shell and lazygit (git repos only), in a new terminal.
# Re-picking a project reattaches to its existing session.
# Projects: git repos up to 3 levels deep, plus every top-level folder,
# under the roots below.
set -euo pipefail

roots=("$HOME/src" "$HOME/work" "$HOME/personal")

projects=$(
    for root in "${roots[@]}"; do
        [ -d "$root" ] || continue
        find "$root" -mindepth 1 -maxdepth 1 -type d -not -name '.*'
        find "$root" -mindepth 2 -maxdepth 4 -type d -name .git -printf '%h\n'
    done | sort -u | sed "s|^$HOME/|~/|"
)

choice=$(printf '%s\n' "$projects" | wofi --dmenu -p "Project" \
    -c "$HOME/.config/wofi/menu-config" --cache-file=/dev/null) || exit 0
[ -n "$choice" ] || exit 0
dir="${choice/#\~/$HOME}"
[ -d "$dir" ] || exit 0

# tmux session names can't contain dots or colons.
session=$(basename "$dir" | tr '.:' '__')

if ! tmux has-session -t "=$session" 2>/dev/null; then
    tmux new-session -d -s "$session" -c "$dir" -n edit nvim
    tmux new-window -t "$session:" -c "$dir" -n shell
    if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        tmux new-window -t "$session:" -c "$dir" -n git lazygit
    fi
    tmux select-window -t "$session:edit"
fi

setsid -f alacritty --title "$session" -e tmux attach-session -t "=$session" >/dev/null 2>&1
