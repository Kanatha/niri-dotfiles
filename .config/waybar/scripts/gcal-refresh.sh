#!/usr/bin/env bash
# Pull today..+8d from Google Calendar (via gcalcli) into a local TSV cache
# that waybar/scripts/calendar.sh and wofi/scripts/gcal-agenda.sh read.
# This is the only place that talks to Google on a schedule; it runs from
# the gcal-refresh systemd user timer and after every add/edit/delete.
#
# Always exits 0. On failure the previous cache is kept and the error is
# written to ~/.cache/gcal-error for the waybar tooltip.
set -uo pipefail

# pipx installs gcalcli here; systemd user units don't have it on PATH.
PATH="$HOME/.local/bin:$PATH"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
cache_file="$cache_dir/gcal-agenda.tsv"
error_file="$cache_dir/gcal-error"
oauth_file="${XDG_DATA_HOME:-$HOME/.local/share}/gcalcli/oauth"
# Present while Google rejects the token. calendar.sh then offers a login
# notification, and clicking the module runs gcal-login.sh.
auth_marker="$cache_dir/gcal-auth-needed"
# Must match the "signal" set on custom/calendar in waybar/config.jsonc.
waybar_signal="RTMIN+10"

mkdir -p "$cache_dir"

# Serialize refreshes (timer + post-write refresh can overlap). Blocking,
# so a refresh right after an add is never skipped in favor of a stale one.
exec 9> "$cache_dir/gcal-refresh.lock"
flock -w 90 9 || exit 0

fail() {
    printf '%s\n' "$1" > "$error_file"
    if [ "${2:-}" = auth ]; then touch "$auth_marker"; else rm -f "$auth_marker"; fi
    pkill -"$waybar_signal" waybar 2>/dev/null || true
    exit 0
}

command -v gcalcli >/dev/null || fail "gcalcli is not installed"
# Without a token gcalcli would start the interactive OAuth flow and wait
# for a browser forever, so bail out before calling it.
[ -s "$oauth_file" ] || fail "Not logged in to Google. Click to log in." auth

tmp=$(mktemp "$cache_file.XXXXXX")
err_tmp=$(mktemp "$error_file.XXXXXX")
trap 'rm -f "$tmp" "$err_tmp"' EXIT

if timeout 60 gcalcli --nocolor agenda --tsv \
        --details id --details url --details location --details calendar \
        "$(date -I)" "$(date -I -d '+8 days')" \
        < /dev/null > "$tmp" 2> "$err_tmp" \
   && head -n1 "$tmp" | grep -q 'start_date'; then
    mv -f "$tmp" "$cache_file"
    rm -f "$error_file" "$auth_marker" "$cache_dir/gcal-auth-notified"
    pkill -"$waybar_signal" waybar 2>/dev/null || true
else
    status=$?
    # Last line of the traceback; for Google API errors just the message.
    msg=$(grep -v '^\s*$' "$err_tmp" | tail -n 1 \
        | sed -E 's/.*returned "([^"]*)".*/\1/; s/ Enable it by visiting.*//')
    if grep -q 'accessNotConfigured' "$err_tmp"; then
        msg="Google Calendar API is disabled in your Cloud project. Enable it in APIs & Services → Library."
    elif grep -qE 'RefreshError|invalid_grant|invalid_client|unauthorized_client|UnpicklingError' "$err_tmp"; then
        # Only real auth failures: offline errors during a token refresh
        # (TransportError) must not ask for a new login.
        fail "Google login expired. Click to log in." auth
    elif [ "$status" -eq 124 ]; then
        msg="Timed out talking to Google Calendar"
    fi
    fail "${msg:-gcalcli failed (exit $status)}"
fi
