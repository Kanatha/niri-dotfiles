#!/usr/bin/env bash
# Clipboard history picker: cliphist + wofi, with image thumbnails.
# Bound to Mod+V in niri. Does not require gawk/ripgrep, just bash+coreutils
# and ImageMagick (for thumbnailing images).
set -euo pipefail

thumb_dir="${XDG_CACHE_HOME:-$HOME/.cache}/cliphist/thumbs"
mkdir -p "$thumb_dir"

cliphist_list="$(cliphist list)"
[ -z "$cliphist_list" ] && exit 0

# Drop cached thumbnails for entries no longer in cliphist's history.
for thumb in "$thumb_dir"/*; do
    [ -e "$thumb" ] || continue
    id="${thumb##*/}"
    id="${id%.*}"
    grep -q "^${id}$(printf '\t')" <<< "$cliphist_list" || rm -f "$thumb"
done

# Build the entry list: image rows become "img:<thumbnail path>",
# everything else passes through as-is ("<id>\t<preview text>").
entries=""
while IFS= read -r line; do
    id="${line%%$'\t'*}"
    if [[ "$line" =~ ^[0-9]+$'\t'\[\[\ binary\ data.*\ (jpg|jpeg|png|bmp)\  ]]; then
        ext="${BASH_REMATCH[1]}"
        thumb="$thumb_dir/$id.$ext"
        if [ ! -f "$thumb" ]; then
            printf '%s\t' "$id" | cliphist decode | magick - -resize '200x200>' "$thumb" 2>/dev/null || continue
        fi
        entries+="img:$thumb"$'\n'
    else
        entries+="$line"$'\n'
    fi
done <<< "$cliphist_list"

choice=$(printf '%s' "$entries" | wofi --dmenu -I -c "$HOME/.config/wofi/clipboard-config" --cache-file=/dev/null)
[ -z "$choice" ] && exit 0

if [[ "$choice" == img:* ]]; then
    thumb_file="${choice#img:}"
    id="${thumb_file##*/}"
    id="${id%.*}"
else
    id="${choice%%$'\t'*}"
fi

printf '%s\t' "$id" | cliphist decode | wl-copy
