# Google Calendar integration: spec

Scope: (A) gcalcli + wofi workflow, (C) waybar calendar popup and next-event display.
Follows the existing pattern of `custom/notifications` (script + signal + wofi picker).

## 1. Requirements

### Functional
| ID | Requirement |
|----|-------------|
| F1 | Add an event from a wofi prompt chain: title -> date -> start time -> duration (or "all day") -> optional location. Event is created in the chosen Google calendar. |
| F2 | Show an agenda (today + next 7 days) in wofi, grouped by day, newest-first not required (chronological). |
| F3 | Selecting an agenda entry offers: Delete, Edit title, Open in browser. |
| F4 | Accept natural-language dates/times ("tomorrow", "fri 14:30", "2026-10-05"). |
| F5 | Waybar module `custom/calendar` shows the next upcoming event (`<icon> 14:30 Standup`), or just the icon when nothing in the next 24h. |
| F6 | `custom/calendar` tooltip lists today's remaining events. |
| F7 | `clock#date` hover tooltip shows a month calendar (read-only, built into waybar); scroll changes month. |
| F8 | Left-click `custom/calendar` -> agenda (F2); right-click -> add event (F1). Optional niri keybind for add event. |
| F9 | Module refreshes every 5 min and immediately (signal) after any add/edit/delete. |
| F10 | Optional: urgent styling (class `soon`) when an event starts in < 10 min; optional `notify-send` reminder via mako. |

### Non-functional
- Waybar must never block on the network: the module reads a local cache; a separate refresh step talks to Google.
- Works offline: shows last cached data, marked stale (class `stale`) if the cache is older than 30 min.
- No secrets in the repo: OAuth tokens stay in `~/.local/share/gcalcli/` (mode 600).
- Styling uses existing `@accent` / `@fg-dim` tokens in `style.css`.
- Failure (no auth, no network) degrades to an icon plus an explanatory tooltip, never an empty or broken bar.

### Dependencies
- `gcalcli` (Debian package, or `pipx install gcalcli`), `wofi`, `jq`, `libnotify-bin` (optional), `python3` (already used).
- Google account with a **Google Cloud project**, **Calendar API enabled**, and an **OAuth client ID (Desktop app)**; the consent screen set to "Testing" with the user as a test user.

## 2. Architecture

```
 Google Calendar API
        ^  |
        |  v
    gcalcli  <----- gcal-refresh.sh (timer / on demand)
        |                |
        |                v
        |      ~/.cache/gcal-agenda.tsv   (cache, 7 days ahead)
        |                |
        v                v
 gcal-add.sh      waybar/scripts/calendar.sh --> custom/calendar (JSON)
 gcal-agenda.sh   (reads cache only)
   (wofi UIs)
```

### Files (all under `~/.config`)
| File | Purpose |
|------|---------|
| `waybar/scripts/calendar.sh` | Emits waybar JSON from the cache: text, tooltip, class. |
| `waybar/scripts/gcal-refresh.sh` | Runs `gcalcli agenda --tsv` for today..+7d, writes cache atomically (tmp + mv), then `pkill -RTMIN+10 waybar`. |
| `wofi/scripts/gcal-add.sh` | Prompt chain for F1, calls `gcalcli add`, then refresh. |
| `wofi/scripts/gcal-agenda.sh` | Agenda picker (F2/F3). |
| `waybar/config.jsonc` | Add `custom/calendar` (signal 10, interval 300, click actions) and calendar tooltip config on `clock#date`. |
| `waybar/style.css` | `#custom-calendar` plus `.soon`, `.stale` classes. |
| `niri/config.kdl` | Optional keybind for add event; optional `spawn-at-startup` for a refresh loop or a systemd user timer. |

Waybar signal 10 is free (8 = monitor, 9 = notifications).

## 3. Detailed behavior

### Setup (one time, manual)
1. Create a Google Cloud project, enable the **Google Calendar API**, and create an OAuth client ID (Desktop).
2. `gcalcli --client-id=<ID> --client-secret=<SECRET> list` and complete the browser consent. gcalcli stores the token.
3. Verify with `gcalcli agenda`.

### gcal-refresh.sh
- `gcalcli agenda --tsv --details location "$(date -I)" "$(date -I -d '+8 days')"` -> cache.
- Exits 0 even on failure and keeps the old cache; writes the error to `~/.cache/gcal-error` for the tooltip.
- Triggered by: the waybar module's `interval`, a systemd user timer (preferred), or after any write action.

### calendar.sh (F5, F6, F10)
- Parse the cache; pick the first event whose end is after now.
- Text: `  HH:MM Title`, truncated to ~28 chars; all-day events show `  Title`.
- Class: `soon` if it starts within 10 min, `stale` if the cache is older than 30 min, else `ok`.
- Tooltip: today's remaining events, one per line, escaped for Pango (`&`, `<`).
- Optional reminder: if an event starts in 10 min and no marker file `~/.cache/gcal-notified-<id>` exists, run `notify-send` and create the marker.

### gcal-add.sh (F1, F4)
1. `wofi --dmenu -p "Title"` (free text, empty = cancel).
2. Calendar choice, only if more than one writable calendar (from `gcalcli list`).
3. Date prompt with suggestions (Today, Tomorrow, next 7 weekdays); free text is passed through `date -d` for validation.
4. Start-time prompt (suggest 09:00..18:00 in 30-minute steps, or "All day").
5. Duration prompt (15m, 30m, 1h, 2h, custom).
6. Run `gcalcli --calendar "<cal>" add --title ... --when ... --duration ... --noprompt`.
7. Refresh the cache, `notify-send "Event added"`; on error show the gcalcli message.
- Esc at any step cancels with no side effects.

### gcal-agenda.sh (F2, F3)
- List from the cache with day headers; label `Mon 05  14:30  Standup  @Room`.
- Selecting an event opens a second wofi: Open in browser (`xdg-open` on the event link), Edit title, Delete (with a Yes/No confirm), Back.
- Delete and edit use `gcalcli delete`/`edit`, then a refresh.

### Waybar config (sketch)
```jsonc
"custom/calendar": {
    "exec": "~/.config/waybar/scripts/calendar.sh",
    "return-type": "json",
    "interval": 300,
    "signal": 10,
    "on-click": "~/.config/wofi/scripts/gcal-agenda.sh",
    "on-click-right": "~/.config/wofi/scripts/gcal-add.sh"
},
"clock#date": {
    "format": "{:%a %d %b}",
    "tooltip-format": "<tt>{calendar}</tt>",
    "calendar": { "mode": "month", "on-scroll": 1,
                  "format": { "today": "<span color='#...'><b>{}</b></span>" } },
    "actions": { "on-scroll-up": "shift_up", "on-scroll-down": "shift_down" }
}
```
Add `"custom/calendar"` to `modules-right` before `clock#date`.

## 4. Edge cases
- Not authenticated or token revoked: tooltip says "Run gcalcli to re-authorize"; the icon is dimmed.
- Multi-day or all-day events: appear on each day; all-day events sort first.
- Overlapping events: the one starting soonest wins for the bar text.
- Timezone: use the system timezone; gcalcli handles conversion.
- Titles containing tabs, quotes or markup: always pass as quoted arguments and escape for Pango.
- Wofi prompts run in a non-interactive session: all failures surface via `notify-send`, not stderr.
- Google "Testing"-mode OAuth refresh tokens expire after 7 days. Either publish the consent screen as "In production" (fine for a personal app, with an unverified warning) or re-auth weekly.

## 5. Acceptance criteria
1. Adding "Test" tomorrow 10:00 for 1h via wofi appears in Google Calendar on the web within 10 s.
2. The waybar module shows the next event within 10 s of the add (signal refresh).
3. With the network off, the bar still renders from the cache and goes `stale` after 30 min.
4. Hovering the date shows a month calendar; scrolling changes month.
5. Deleting an event from the agenda removes it from Google and the bar.
6. No gcalcli invocation happens inside `calendar.sh` (verified by running it with the network off; it returns in < 100 ms).

## 6. Build order
1. Google Cloud setup and gcalcli auth (manual, about 10 min).
2. `gcal-refresh.sh` and `calendar.sh`, then the waybar module and styling.
3. Clock calendar tooltip (pure config).
4. `gcal-add.sh`.
5. `gcal-agenda.sh` with edit/delete.
6. Reminders (`soon` class, notify-send) and the niri keybind.
7. Timer for periodic refresh.

## 7. Open decisions
- Which calendars to show: all, or only selected ones (`--calendar` filter)?
- Reminders via mako: yes/no, and the lead time.
- Refresh mechanism: systemd user timer (recommended) vs. waybar interval only.
- Keybind for add event: which key?
