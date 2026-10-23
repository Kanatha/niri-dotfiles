#!/usr/bin/env bash
# Status for custom/calendar: next upcoming Google Calendar event, from the
# cache written by gcal-refresh.sh. Never touches the network (waybar must
# not block), so it's cheap enough to run every minute: that keeps the
# "soon" class and the 10-minute reminder on time.
#
# Left-click opens wofi/scripts/gcal-agenda.sh, right-click gcal-add.sh.
set -euo pipefail

exec python3 - <<'EOF'
import csv, html, json, os, re, subprocess, sys, time
from datetime import datetime, timedelta

ICON = ""          # nf-fa-calendar
MAX_TEXT = 28
SOON = timedelta(minutes=10)
STALE_AFTER = 30 * 60

cache_dir = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
cache_file = os.path.join(cache_dir, "gcal-agenda.tsv")
error_file = os.path.join(cache_dir, "gcal-error")
auth_marker = os.path.join(cache_dir, "gcal-auth-needed")
auth_notified = os.path.join(cache_dir, "gcal-auth-notified")
login = os.path.expanduser("~/.config/waybar/scripts/gcal-login.sh")

now = datetime.now()
today = now.date()


def esc(s):
    return html.escape(s, quote=False)


def emit(text, tooltip, classes):
    print(json.dumps({"text": text, "tooltip": tooltip, "class": classes}))
    sys.exit(0)


def read_error():
    try:
        with open(error_file) as f:
            return f.read().strip()
    except OSError:
        return ""


def parse(date, time_):
    return datetime.strptime(f"{date} {time_ or '00:00'}", "%Y-%m-%d %H:%M")


error = read_error()

# Login expired: one notification per expiry; clicking it (or the module,
# see gcal-agenda.sh / gcal-add.sh) opens the Google login page. Detached
# so it outlives this script while the notification waits for a click.
if os.path.exists(auth_marker) and not os.path.exists(auth_notified):
    open(auth_notified, "w").close()
    try:
        subprocess.Popen(
            ["sh", "-c", 'a=$(notify-send -a Calendar -i x-office-calendar -u critical '
                         '-A default="Log in" --wait "Calendar login expired" '
                         '"Click to log in to Google Calendar") '
                         '&& [ "$a" = default ] && exec "$0"', login],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        pass
try:
    cache_age = time.time() - os.path.getmtime(cache_file)
    with open(cache_file, newline="") as f:
        rows = list(csv.DictReader(f, dialect="excel-tab", quoting=csv.QUOTE_NONE))
except OSError:
    emit(ICON, esc(error or "No calendar data yet (gcal-refresh.sh hasn't run)"),
         ["error", "auth"] if os.path.exists(auth_marker) else ["error"])

events = []
for r in rows:
    try:
        all_day = not r.get("start_time")
        start = parse(r["start_date"], r.get("start_time"))
        end = parse(r["end_date"], r.get("end_time"))
    except (KeyError, ValueError, TypeError):
        continue
    events.append({
        "id": r.get("id", ""),
        "title": (r.get("title") or "(No title)").strip(),
        "location": (r.get("location") or "").strip(),
        "all_day": all_day,
        "start": start,
        # Google's all-day end date is exclusive, so end == next midnight.
        "end": end,
    })
events.sort(key=lambda e: (e["start"], not e["all_day"]))

# Bar text: the timed event that is running or starts soonest within 24h.
# All-day events only show when there's no timed one: since they "start" at
# midnight they would otherwise hide every real appointment of the day.
horizon = now + timedelta(hours=24)
timed = [e for e in events if not e["all_day"] and e["end"] > now and e["start"] < horizon]
all_day_today = [e for e in events if e["all_day"] and e["start"].date() <= today < e["end"].date()]

classes = []
if timed:
    nxt = timed[0]
    label = f"{nxt['start']:%H:%M} {nxt['title']}"
    if timedelta(0) <= nxt["start"] - now <= SOON:
        classes.append("soon")
elif all_day_today:
    label = all_day_today[0]["title"]
else:
    label = ""

if label:
    if len(label) > MAX_TEXT:
        label = label[:MAX_TEXT - 1] + "…"
    text = f"{ICON}  {label}"
    classes.append("ok")
else:
    text = ICON
    classes.append("empty")

# Tooltip: everything still ahead today (multi-day events included).
midnight = datetime.combine(today, datetime.min.time()) + timedelta(days=1)
lines = []
for e in events:
    if e["end"] <= now or e["start"] >= midnight:
        continue
    if e["all_day"]:
        when = "all day"
    elif e["start"] < now:
        when = f"now → {e['end']:%H:%M}" if e["end"].date() == today else "now"
    else:
        when = f"{e['start']:%H:%M}"
    line = f"<b>{esc(when)}</b>  {esc(e['title'])}"
    if e["location"]:
        line += f"  <i>@{esc(e['location'])}</i>"
    lines.append(line)
tooltip = "\n".join(["<b>Today</b>"] + (lines or ["Nothing else today"]))

if cache_age > STALE_AFTER:
    classes.append("stale")
    tooltip += f"\n\n<i>Last synced {datetime.fromtimestamp(time.time() - cache_age):%a %H:%M}</i>"
if error:
    classes.append("error")
    if os.path.exists(auth_marker):
        classes.append("auth")
    tooltip += f"\n<i>{esc(error)}</i>"

# 10-minute reminder via mako, once per event (marker file per event id).
for e in timed:
    if not e["id"] or not timedelta(0) <= e["start"] - now <= SOON:
        continue
    marker = os.path.join(cache_dir, "gcal-notified-" + re.sub(r"[^A-Za-z0-9_-]", "_", e["id"]))
    if os.path.exists(marker):
        continue
    open(marker, "w").close()
    body = f"{e['start']:%H:%M}" + (f" @ {e['location']}" if e["location"] else "")
    try:
        subprocess.Popen(["notify-send", "-a", "Calendar", "-i", "x-office-calendar",
                          e["title"], body],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass

# Drop reminder markers older than two days.
for name in os.listdir(cache_dir):
    if name.startswith("gcal-notified-"):
        p = os.path.join(cache_dir, name)
        try:
            if time.time() - os.path.getmtime(p) > 2 * 86400:
                os.remove(p)
        except OSError:
            pass

emit(text, tooltip, classes)
EOF
