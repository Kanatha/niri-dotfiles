#!/usr/bin/env bash
# Add a Google Calendar event via a wofi prompt chain + gcalcli:
# title -> calendar (if more than one writable) -> date -> start time ->
# duration -> location. Each list prompt also accepts free text, parsed
# with `date -d` ("tomorrow", "fri 14:30", "2026-10-05", "2pm", ...).
# Esc at any step cancels without side effects.
# Bound to right-click on waybar's custom/calendar and Mod+E in niri.
set -euo pipefail

PATH="$HOME/.local/bin:$PATH"

wofi_gcal=(wofi --dmenu -c "$HOME/.config/wofi/gcal-config" --cache-file=/dev/null)
refresh="$HOME/.config/waybar/scripts/gcal-refresh.sh"

notify() { notify-send -a Calendar -i x-office-calendar "$@" 2>/dev/null || true; }
die() { notify -u critical "Calendar: $1" "${2:-}"; exit 1; }

# pick PROMPT < options  (empty result = cancelled)
pick() { "${wofi_gcal[@]}" -p "$1" || true; }
# ask PROMPT  (free text only)
ask() { printf '' | "${wofi_gcal[@]}" --exec-search -p "$1" || true; }

# True if a free-text date also carries a time ("fri 14:30", "tomorrow 9am").
has_time() { grep -qiE '[0-9]:[0-9]|[0-9] ?(am|pm)\b|\bnoon\b' <<< "$1"; }

# Google login expired: send the click/keybind to the login page instead.
[ -e "${XDG_CACHE_HOME:-$HOME/.cache}/gcal-auth-needed" ] \
    && exec "$HOME/.config/waybar/scripts/gcal-login.sh"

# 1. Title
title=$(ask "Title")
title=${title//$'\t'/ }
[ -z "${title// /}" ] && exit 0

# 2. Calendar (only writable ones; skip the prompt if there's just one).
# `gcalcli list` rows look like "  owner  Name" / " writer  Name".
calendars=$(timeout 30 gcalcli --nocolor list < /dev/null 2>/dev/null \
    | sed -nE 's/^ *(owner|writer) +//p') \
    || die "couldn't list calendars" "Check your network or run gcalcli init."
[ -n "$calendars" ] || die "no writable calendars found"
if [ "$(wc -l <<< "$calendars")" -gt 1 ]; then
    calendar=$(pick "Calendar" <<< "$calendars")
    [ -z "$calendar" ] && exit 0
    grep -qxF -- "$calendar" <<< "$calendars" || die "unknown calendar" "$calendar"
else
    calendar=$calendars
fi

# 3. Date: Today, Tomorrow, then the following week by name.
declare -A date_by_label=([Today]=$(date +%F) [Tomorrow]=$(date -d tomorrow +%F))
date_menu=$'Today\nTomorrow\n'
for i in 2 3 4 5 6 7 8; do
    label=$(date -d "+$i days" '+%a %d %b')
    date_by_label[$label]=$(date -d "+$i days" +%F)
    date_menu+="$label"$'\n'
done

when_in=$(pick "Date" <<< "$date_menu")
[ -z "$when_in" ] && exit 0
start_time=""
if [ -n "${date_by_label[$when_in]:-}" ]; then
    day=${date_by_label[$when_in]}
else
    day=$(date -d "$when_in" +%F 2>/dev/null) || die "couldn't understand the date" "$when_in"
    has_time "$when_in" && start_time=$(date -d "$when_in" +%H:%M)
fi

# 4. Start time (skipped if the date already had one).
all_day=false
if [ -z "$start_time" ]; then
    time_menu="All day"
    for m in $(seq 540 30 1080); do  # 09:00 .. 18:00
        time_menu+=$(printf '\n%02d:%02d' $((m / 60)) $((m % 60)))
    done
    time_in=$(pick "Start ($(date -d "$day" '+%a %d %b'))" <<< "$time_menu")
    [ -z "$time_in" ] && exit 0
    if [ "$time_in" = "All day" ]; then
        all_day=true
    else
        start_time=$(date -d "$day $time_in" +%H:%M 2>/dev/null) \
            || die "couldn't understand the time" "$time_in"
    fi
fi

# 5. Duration in minutes (all-day events are one day long).
to_minutes() {
    local s=${1,,}; s=${s// /}
    if [[ $s =~ ^([0-9]+)h(([0-9]+)m?)?$ ]]; then
        echo $(( BASH_REMATCH[1] * 60 + ${BASH_REMATCH[3]:-0} ))
    elif [[ $s =~ ^([0-9]+)(m|min)?$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        return 1
    fi
}
duration=1
if ! $all_day; then
    dur_in=$(pick "Duration" <<< $'1h\n30m\n15m\n2h\nCustom...')
    [ -z "$dur_in" ] && exit 0
    if [ "$dur_in" = "Custom..." ]; then
        dur_in=$(ask "Duration (e.g. 45m, 1h30)")
        [ -z "$dur_in" ] && exit 0
    fi
    duration=$(to_minutes "$dur_in") && [ "$duration" -gt 0 ] \
        || die "couldn't understand the duration" "$dur_in"
fi

# 6. Location (optional).
location=$(pick "Location (optional)" <<< "No location")
[ -z "$location" ] && exit 0
[ "$location" = "No location" ] && location=""

# 7. Create it.
args=(add --calendar "$calendar" --title "$title" --duration "$duration"
      --default-reminders --noprompt)
if $all_day; then
    args+=(--allday --when "$day")
    summary="$(date -d "$day" '+%a %d %b'), all day"
else
    args+=(--when "$day $start_time")
    summary="$(date -d "$day" '+%a %d %b') $start_time ($dur_in)"
fi
[ -n "$location" ] && args+=(--where "$location")

if ! err=$(timeout 60 gcalcli --nocolor "${args[@]}" < /dev/null 2>&1 >/dev/null); then
    die "couldn't add event" "$(grep -v '^\s*$' <<< "$err" | tail -n1)"
fi

"$refresh"
notify "Event added" "$title — $summary"
