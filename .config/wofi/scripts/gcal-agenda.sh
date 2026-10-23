#!/usr/bin/env bash
# Google Calendar agenda (today + 7 days) in wofi, read from the cache that
# waybar/scripts/gcal-refresh.sh writes. Selecting an event offers Open in
# browser / Edit title / Delete; edits and deletes go through
# `gcalcli agendaupdate` by event id (unlike `gcalcli delete`, which matches
# titles by regex), then refresh the cache.
# Bound to left-click on waybar's custom/calendar.
set -euo pipefail

PATH="$HOME/.local/bin:$PATH"

wofi_gcal=(wofi --dmenu -c "$HOME/.config/wofi/gcal-config" --cache-file=/dev/null)
cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/gcal-agenda.tsv"
refresh="$HOME/.config/waybar/scripts/gcal-refresh.sh"

notify() { notify-send -a Calendar -i x-office-calendar "$@" 2>/dev/null || true; }
pick() { "${wofi_gcal[@]}" -p "$1" || true; }

# Google login expired: send the click to the login page instead.
[ -e "${XDG_CACHE_HOME:-$HOME/.cache}/gcal-auth-needed" ] \
    && exec "$HOME/.config/waybar/scripts/gcal-login.sh"

[ -s "$cache_file" ] || {
    notify -u critical "Calendar: no data" \
        "$(cat "${XDG_CACHE_HOME:-$HOME/.cache}/gcal-error" 2>/dev/null || echo 'Run gcal-refresh.sh')"
    exit 1
}

# Menu rows: label, id, calendar, link, title separated by \x1f (not tabs:
# `read` collapses runs of IFS whitespace, which would shift empty fields).
# Day headers have no id.
# Multi-day / all-day events are listed under every day they cover.
build_menu() {
    python3 - "$cache_file" <<'EOF'
import csv, sys
from datetime import date, datetime, timedelta

now = datetime.now()
days = [now.date() + timedelta(days=i) for i in range(8)]
by_day = {d: [] for d in days}

with open(sys.argv[1], newline="") as f:
    for r in csv.DictReader(f, dialect="excel-tab", quoting=csv.QUOTE_NONE):
        try:
            all_day = not r.get("start_time")
            start = datetime.strptime(f"{r['start_date']} {r.get('start_time') or '00:00'}", "%Y-%m-%d %H:%M")
            end = datetime.strptime(f"{r['end_date']} {r.get('end_time') or '00:00'}", "%Y-%m-%d %H:%M")
        except (KeyError, ValueError, TypeError):
            continue
        if end <= now:
            continue
        for d in days:
            day_start = datetime.combine(d, datetime.min.time())
            if start < day_start + timedelta(days=1) and end > day_start:
                by_day[d].append((r, all_day, start))

def clean(s):
    return (s or "").replace("\t", " ").replace("\x1f", " ").strip()

for d in days:
    items = sorted(by_day[d], key=lambda x: (not x[1], x[2]))
    if not items:
        continue
    head = "Today" if d == now.date() else "Tomorrow" if d == now.date() + timedelta(days=1) else f"{d:%A}"
    print(f"── {head}, {d:%d %b} ──" + "\x1f" * 4)
    for r, all_day, start in items:
        title = clean(r.get("title")) or "(No title)"
        when = "all-day" if all_day else (f"{start:%H:%M}" if start.date() == d else "cont.")
        label = f"{d:%a %d}  {when:>7}  {title}"
        if clean(r.get("location")):
            label += f"  @{clean(r['location'])}"
        print("\x1f".join([label, clean(r.get("id")), clean(r.get("calendar")),
                         clean(r.get("html_link")), title]))
EOF
}

# Feed one row to `gcalcli agendaupdate` (TSV with proper quoting).
agenda_update() {  # calendar header... -- values...
    local cal=$1; shift
    python3 -c '
import csv, sys
args = sys.argv[1:]
i = args.index("--")
w = csv.writer(sys.stdout, dialect="excel-tab", lineterminator="\n")
w.writerow(args[:i]); w.writerow(args[i + 1:])
' "$@" | timeout 60 gcalcli --nocolor --calendar "$cal" agendaupdate 2>&1 >/dev/null \
        | grep -v '^\s*$' | tail -n1
    return "${PIPESTATUS[1]}"
}

while true; do
    menu=$(build_menu)
    if [ -z "$menu" ]; then
        notify "Calendar" "Nothing in the next 7 days"
        exit 0
    fi

    choice=$(pick "Agenda" <<< "$(cut -d $'\x1f' -f1 <<< "$menu")")
    [ -z "$choice" ] && exit 0

    row=$(awk -F'\x1f' -v c="$choice" '$1 == c { print; exit }' <<< "$menu")
    IFS=$'\x1f' read -r _ id calendar link title <<< "$row" || true
    # Day header, or free text that matched nothing: show the list again.
    [ -z "${id:-}" ] && continue

    actions=""
    [ -n "$link" ] && actions+="Open in browser"$'\n'
    actions+=$'Edit title\nDelete\nBack'

    case "$(pick "$title" <<< "$actions")" in
        "Open in browser")
            xdg-open "$link" >/dev/null 2>&1 &
            exit 0
            ;;
        "Edit title")
            new_title=$(printf '' | "${wofi_gcal[@]}" --exec-search -p "New title (was: $title)" || true)
            new_title=${new_title//$'\t'/ }
            [ -z "${new_title// /}" ] && continue
            if err=$(agenda_update "$calendar" id title -- "$id" "$new_title"); then
                "$refresh"
                notify "Event renamed" "$title → $new_title"
            else
                notify -u critical "Calendar: couldn't rename event" "$err"
            fi
            exit 0
            ;;
        "Delete")
            confirm=$(pick "Delete \"$title\"?" <<< $'No\nYes')
            [ "$confirm" = "Yes" ] || continue
            if err=$(agenda_update "$calendar" id action -- "$id" delete); then
                "$refresh"
                notify "Event deleted" "$title"
            else
                notify -u critical "Calendar: couldn't delete event" "$err"
            fi
            exit 0
            ;;
        *)  # Back / Esc
            continue
            ;;
    esac
done
