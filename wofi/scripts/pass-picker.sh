#!/usr/bin/env bash
# Password manager: list/copy/generate/delete entries via wofi + pass.
# Bound to Mod+P in niri. Selecting an entry copies its password to the
# clipboard (auto-cleared by `pass` after its default 45s).
set -euo pipefail

wofi_pass=(wofi --dmenu -c "$HOME/.config/wofi/pass-config" --cache-file=/dev/null)
new_entry="New Password"
store_dir="${PASSWORD_STORE_DIR:-$HOME/.password-store}"

# Run a `pass` command that copies a secret to the clipboard (show -c /
# generate -c), then scrub it back out of cliphist's history.
#
# Pausing or restarting the cliphist watcher does NOT work here: Wayland
# queues the clipboard-changed notification at the socket level (so a
# paused watcher still sees it once resumed), and `wl-paste --watch` fires
# immediately for whatever's already on the clipboard the moment it
# (re)starts. So the secret briefly touches cliphist's db either way; this
# reads it straight back off the clipboard and deletes the matching entry
# a moment later, before anyone opens the clipboard picker.
clip_copy() {
    "$@" >/dev/null
    sleep 0.3
    local secret
    secret=$(wl-paste -n 2>/dev/null || true)
    [ -n "$secret" ] || return 0
    cliphist list | grep -F -- "$secret" | cliphist delete 2>/dev/null || true
}

entries=$(find "$store_dir" -type f -name '*.gpg' 2>/dev/null \
    | sed "s#^$store_dir/##; s#\.gpg\$##" | sort)

choice=$(printf '%s\n%s\n' "$new_entry" "$entries" | "${wofi_pass[@]}")
[ -z "$choice" ] && exit 0

if [ "$choice" = "$new_entry" ]; then
    name=$(printf '' | wofi --dmenu --exec-search -p "New password name" \
        -c "$HOME/.config/wofi/pass-config" --cache-file=/dev/null) || true
    [ -z "$name" ] && exit 0

    case "$(printf 'Generate random\nType my own\n' | wofi --dmenu -p "$name" \
        -c "$HOME/.config/wofi/pass-config" --cache-file=/dev/null)" in
        "Generate random")
            clip_copy pass generate -c "$name" 20
            ;;
        "Type my own")
            secret=$(printf '' | wofi --dmenu --exec-search --password \
                -p "Password for $name" \
                -c "$HOME/.config/wofi/pass-config" --cache-file=/dev/null) || true
            [ -z "$secret" ] && exit 0
            printf '%s\n' "$secret" | pass insert -e -f "$name" >/dev/null
            clip_copy pass show -c "$name"
            ;;
    esac
    exit 0
fi

case "$(printf 'Copy\nDelete\n' | wofi --dmenu -p "$choice" -c "$HOME/.config/wofi/pass-config" --cache-file=/dev/null)" in
    Copy)
        clip_copy pass show -c "$choice"
        ;;
    Delete)
        confirm=$(printf 'No\nYes\n' | wofi --dmenu -p "Delete \"$choice\"?" \
            -c "$HOME/.config/wofi/pass-config" --cache-file=/dev/null)
        [ "$confirm" = "Yes" ] && pass rm -f "$choice" >/dev/null
        ;;
esac
