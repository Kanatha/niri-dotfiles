#!/usr/bin/env bash
# Re-authorize gcalcli with Google: opens the consent page in the browser,
# catches the redirect on a localhost port and saves the token where
# gcalcli reads it. Same flow as `gcalcli init`, minus its terminal-only
# prompts, so it can run from a waybar click or a notification action.
#
# The OAuth client ID/secret come from the current token (it embeds them)
# and are also kept in ~/.local/share/gcalcli/client.json (mode 600), so
# this keeps working after the token itself is gone.
set -euo pipefail

PATH="$HOME/.local/bin:$PATH"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/gcalcli"
refresh="$HOME/.config/waybar/scripts/gcal-refresh.sh"

notify() { notify-send -a Calendar -i x-office-calendar "$@" 2>/dev/null || true; }

# One login flow at a time (double clicks, notification + click).
exec 9> "$cache_dir/gcal-login.lock"
flock -n 9 || exit 0

gcalcli_bin=$(command -v gcalcli) || { notify -u critical "Calendar" "gcalcli is not installed"; exit 1; }
# gcalcli's own (pipx venv) python has google-auth-oauthlib installed.
python=$(sed -n '1s/^#!//p' "$gcalcli_bin")

mkdir -p "$data_dir"
if ! err=$(timeout 330 "$python" - "$data_dir" 2>&1 <<'EOF'
import json, os, pickle, sys
from google_auth_oauthlib.flow import InstalledAppFlow

data_dir = sys.argv[1]
oauth = os.path.join(data_dir, "oauth")
client_file = os.path.join(data_dir, "client.json")

client = None
try:
    with open(oauth, "rb") as f:
        creds = pickle.load(f)
    if creds.client_id and creds.client_secret:
        client = {"client_id": creds.client_id, "client_secret": creds.client_secret}
except Exception:
    pass
if client is None:
    try:
        with open(client_file) as f:
            client = json.load(f)
    except OSError:
        sys.exit("No OAuth client ID known yet. Run once in a terminal: "
                 "gcalcli --client-id=ID --client-secret=SECRET init")

# Remember the client for next time (it's a secret: owner-only).
fd = os.open(client_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    json.dump(client, f)

# Same client config and scope as gcalcli/auth.py.
flow = InstalledAppFlow.from_client_config(
    {"installed": {**client,
                   "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                   "token_uri": "https://oauth2.googleapis.com/token",
                   "redirect_uris": ["http://localhost"]}},
    scopes=["https://www.googleapis.com/auth/calendar"],
)
creds = flow.run_local_server(
    port=0, open_browser=True, timeout_seconds=300,
    success_message="Google Calendar is connected. You can close this tab.",
)
if not creds or not creds.refresh_token:
    sys.exit("Login was not completed.")

tmp = oauth + ".tmp"
fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "wb") as f:
    pickle.dump(creds, f)
os.replace(tmp, oauth)
EOF
); then
    msg=$(grep -v '^\s*$' <<< "$err" | tail -n 1)
    [ -z "$msg" ] && msg="Login timed out"
    notify -u critical "Calendar login failed" "$msg"
    exit 1
fi

"$refresh"
if [ -e "$cache_dir/gcal-auth-needed" ]; then
    notify -u critical "Calendar" "Logged in, but Google still rejects the token: $(cat "$cache_dir/gcal-error" 2>/dev/null)"
    exit 1
fi
notify "Calendar connected" "Logged in to Google Calendar"
