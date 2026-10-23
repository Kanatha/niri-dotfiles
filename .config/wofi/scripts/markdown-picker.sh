#!/usr/bin/env bash
# Markdown doc browser: navigate directories like a file explorer, starting
# at $HOME, until you pick a .md file — which opens rendered (real headers/
# bold/lists/code blocks, via glow + a Nord glamour style at
# ~/.config/glow/nord.json), not just raw text. Press 'e' inside glow to
# edit, '/' to search, q to close. No delete here on purpose — this can
# reach arbitrary project files, unlike the notes manager's own folder.
set -euo pipefail

search_root="$HOME"
current="$search_root"

up_marker=".. (up)"

view_file() {
    local file="$1"
    alacritty --class quick-editor -e env EDITOR=nvim \
        glow --style "$HOME/.config/glow/nord.json" --pager "$file"
}

while true; do
    entries=""
    [ "$current" != "$search_root" ] && entries+="$up_marker"$'\n'

    # subdirectories at this level, hidden dirs included
    # (common noise dirs like node_modules/vendor still excluded)
    while IFS= read -r -d '' d; do
        entries+="$(basename "$d")/"$'\n'
    done < <(find "$current" -mindepth 1 -maxdepth 1 -type d \
        ! -name node_modules ! -name vendor \
        ! -name target ! -name dist ! -name build \
        -print0 | sort -z)

    # .md files at this level
    while IFS= read -r -d '' f; do
        entries+="$(basename "$f")"$'\n'
    done < <(find "$current" -mindepth 1 -maxdepth 1 -type f -iname '*.md' \
        -print0 | sort -z)

    [ -z "$entries" ] && exit 0

    display_path="${current/#$search_root/~}"
    choice=$(printf '%s' "$entries" | wofi --dmenu -p "$display_path" \
        -c "$HOME/.config/wofi/notes-config" --cache-file=/dev/null)
    [ -z "$choice" ] && exit 0

    if [ "$choice" = "$up_marker" ]; then
        current="$(dirname "$current")"
    elif [[ "$choice" == */ ]]; then
        current="$current/${choice%/}"
    else
        view_file "$current/$choice"
    fi
done
