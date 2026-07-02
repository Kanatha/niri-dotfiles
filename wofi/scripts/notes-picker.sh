#!/usr/bin/env bash
# Note manager: create/edit/delete plain-text notes via wofi.
# Bound to Mod+N in niri. Notes live as one Markdown file per note in
# notes_dir; the first line of each file is treated as its title.
set -euo pipefail

notes_dir="${XDG_DATA_HOME:-$HOME/.local/share}/notes"
mkdir -p "$notes_dir"

wofi_notes=(wofi --dmenu -c "$HOME/.config/wofi/notes-config" --cache-file=/dev/null)

new_entry="New Note"

slugify() {
    local s
    s=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    s=$(printf '%s' "$s" | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')
    [ -n "$s" ] || s="note"
    printf '%s' "$s"
}

open_editor() {
    alacritty --class quick-editor -e nvim "$1"
}

edit_marker="Edit note"
delete_marker="Delete note"

# Show the note's contents, one line per entry, with Edit/Delete appended.
# Selecting a content line copies just that line to the clipboard.
view_note() {
    local file="$1" title="$2" body menu sel confirm
    body=$(grep -v '^$' "$file" || true)
    menu=$(printf '%s\n%s\n%s\n' "$body" "$edit_marker" "$delete_marker")

    sel=$(printf '%s' "$menu" | wofi --dmenu -p "$title" \
        -c "$HOME/.config/wofi/notes-config" --cache-file=/dev/null)
    [ -z "$sel" ] && return

    case "$sel" in
        "$edit_marker")
            open_editor "$file"
            ;;
        "$delete_marker")
            confirm=$(printf 'No\nYes\n' | wofi --dmenu -p "Delete \"$title\"?" \
                -c "$HOME/.config/wofi/notes-config" --cache-file=/dev/null)
            [ "$confirm" = "Yes" ] && rm -f "$file"
            ;;
        *)
            printf '%s' "$sel" | wl-copy
            ;;
    esac
}

create_note() {
    local title file slug base n
    title=$(printf '' | wofi --dmenu --exec-search -p "New note title" \
        -c "$HOME/.config/wofi/notes-config" --cache-file=/dev/null) || true
    [ -z "$title" ] && exit 0

    base=$(slugify "$title")
    slug="$base"
    n=1
    while [ -e "$notes_dir/$slug.md" ]; do
        n=$((n + 1))
        slug="$base-$n"
    done

    file="$notes_dir/$slug.md"
    printf '%s\n\n' "$title" > "$file"
    open_editor "$file"
}

# title -> file path, newest first
declare -A file_by_title
titles=""
while IFS= read -r -d '' file; do
    title=$(head -n1 "$file")
    [ -z "$title" ] && title="$(basename "$file" .md)"
    file_by_title["$title"]="$file"
    titles+="$title"$'\n'
done < <(find "$notes_dir" -maxdepth 1 -name '*.md' -printf '%T@ %p\0' \
    | sort -znr | sed -z 's/^[^ ]* //')

choice=$(printf '%s%s' "$new_entry"$'\n' "$titles" | "${wofi_notes[@]}")
[ -z "$choice" ] && exit 0

if [ "$choice" = "$new_entry" ]; then
    create_note
    exit 0
fi

file="${file_by_title[$choice]:-}"
[ -z "$file" ] && exit 0

view_note "$file" "$choice"
