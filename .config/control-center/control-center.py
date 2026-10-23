#!/usr/bin/env python3
# Android-style quick settings panel, opened from the waybar center module
# (custom/control) and Mod+Grave. Runs as one resident GTK application:
# launching this script again just toggles the panel, so it opens fast.
#
# Layout: left column = quick tiles, sliders, media player; right column =
# system stats, calendar, notifications.
#
# Keyboard (vim motions):
#   j/k        next/previous row          g/G   first/last row
#   h/l        previous/next item, or adjust a slider (H/L = fine steps);
#              at the edge of a row they cross to the other column
#   Tab        switch column              Ctrl-d/u  jump 5 rows
#   Enter/Spc  toggle tile / mute slider / play-pause / open event /
#              dismiss notification / clear all
#   o          open the tile's picker (Wi-Fi networks, Bluetooth devices)
#   x          dismiss notification under cursor
#   D          clear all notifications
#   n          toggle night light
#   q/Esc      close
#
# Mouse: left click = Enter, right click on a tile = o.
#
# System state is read in a background thread once a second while the panel
# is open, so slow commands (bluetoothctl, nmcli) never block the keyboard.
# Notifications come from the log written by mako/notif-history-logger.py;
# night light, focus mode and caffeine are the scripts in ~/.local/bin.

import csv
import json
import os
import subprocess
import sys
import threading
import time
from datetime import datetime

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk, Pango  # noqa: E402

# Layer shell gives a proper overlay below the bar; without the
# gir1.2-gtklayershell-0.1 package it falls back to a floating niri window
# (see the control-center window-rule in niri/config.kdl).
try:
    gi.require_version("GtkLayerShell", "0.1")
    from gi.repository import GtkLayerShell
except (ValueError, ImportError):
    GtkLayerShell = None

import psutil  # noqa: E402

APP_ID = "com.luka.ControlCenter"
HERE = os.path.dirname(os.path.realpath(__file__))
HOME = os.path.expanduser("~")
BIN = os.path.join(HOME, ".local/bin")
CACHE = os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache"))
RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
STATE = os.environ.get("XDG_STATE_HOME", os.path.join(HOME, ".local/state"))
HISTORY_FILE = os.path.join(CACHE, "mako-notif-history.jsonl")
SEEN_FILE = os.path.join(CACHE, "mako-notif-seen")
AGENDA_FILE = os.path.join(CACHE, "gcal-agenda.tsv")
NIGHTLIGHT_DIR = os.path.join(STATE, "nightlight")
FOCUS_FILE = os.path.join(RUNTIME, "focus-mode-end")
CAFFEINE_FILE = os.path.join(RUNTIME, "caffeine")
WOFI_SCRIPTS = os.path.join(HOME, ".config/wofi/scripts")
# Must match the "signal" set on custom/control in waybar/config.jsonc.
WAYBAR_SIGNAL = "RTMIN+9"
POWER_PROFILES = ["power-saver", "balanced", "performance"]


def run(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def spawn(*cmd):
    subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def signal_waybar():
    spawn("pkill", "-" + WAYBAR_SIGNAL, "waybar")


def read_file(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def human_bytes(n):
    for unit in ("B", "K", "M", "G", "T"):
        if n < 1024 or unit == "T":
            return f"{n:.0f}{unit}" if unit == "B" else f"{n:.1f}{unit}"
        n /= 1024


def ago(ts):
    s = max(0, int(time.time()) - ts)
    if s < 60:
        return "now"
    for size, unit in ((86400, "d"), (3600, "h"), (60, "m")):
        if s >= size:
            return f"{s // size}{unit} ago"


def label(text="", css=None, xalign=0.0, **kw):
    lbl = Gtk.Label(label=text, xalign=xalign, **kw)
    if css:
        lbl.get_style_context().add_class(css)
    return lbl


def add_class(widget, *classes):
    ctx = widget.get_style_context()
    for c in classes:
        ctx.add_class(c)


def set_class(widget, cls, on):
    ctx = widget.get_style_context()
    (ctx.add_class if on else ctx.remove_class)(cls)


# ---------- System state (read in a worker thread) ----------

def read_volume(target):
    # "Volume: 0.45 [MUTED]"
    parts = run("wpctl", "get-volume", target).split()
    if len(parts) < 2:
        return None
    try:
        return round(float(parts[1]) * 100), "[MUTED]" in parts
    except ValueError:
        return None


def read_media():
    out = run("playerctl", "metadata", "--format",
              "{{status}}\t{{playerName}}\t{{artist}}\t{{title}}")
    parts = out.split("\t")
    if len(parts) < 4 or parts[0] not in ("Playing", "Paused"):
        return None
    return dict(zip(("status", "player", "artist", "title"), parts))


def read_state():
    s = {}
    s["night"] = (read_file(os.path.join(NIGHTLIGHT_DIR, "enabled"), "on") == "on",
                  int(read_file(os.path.join(NIGHTLIGHT_DIR, "temp"), "4000") or 4000))
    s["dnd"] = "do-not-disturb" in run("makoctl", "mode").split()
    try:
        layouts = json.loads(run("niri", "msg", "--json", "keyboard-layouts"))
        s["layout"] = layouts["names"][layouts["current_idx"]]
    except (ValueError, KeyError, IndexError):
        s["layout"] = "?"
    wifi_on = run("nmcli", "radio", "wifi") == "enabled"
    ssid = ""
    for line in run("nmcli", "-t", "-f", "ACTIVE,SSID", "dev", "wifi").splitlines():
        if line.startswith("yes:"):
            ssid = line[4:].replace("\\:", ":")
            break
    s["wifi"] = (wifi_on, ssid)
    bt_on = "Powered: yes" in run("bluetoothctl", "show")
    connected = [line.split(" ", 2)[2] for line in
                 run("bluetoothctl", "devices", "Connected").splitlines()
                 if line.startswith("Device ") and line.count(" ") >= 2]
    s["bt"] = (bt_on, connected)
    s["profile"] = run("powerprofilesctl", "get") or None
    s["caffeine"] = os.path.exists(CAFFEINE_FILE)
    end = read_file(FOCUS_FILE)
    s["focus"] = max(0, (int(end) - int(time.time()) + 59) // 60) if end.isdigit() else None
    fields = run("brightnessctl", "--class=backlight", "-m").split(",")
    s["brightness"] = int(fields[3].rstrip("%")) if len(fields) > 3 else None
    s["volume"] = read_volume("@DEFAULT_AUDIO_SINK@")
    s["mic"] = read_volume("@DEFAULT_AUDIO_SOURCE@")
    s["media"] = read_media()
    return s


def read_history():
    try:
        with open(HISTORY_FILE) as f:
            entries = [json.loads(line) for line in f if line.strip()]
    except (OSError, ValueError):
        return []
    return entries[::-1]  # newest first


def read_agenda(limit=4):
    """Upcoming events from the cache written by waybar/scripts/gcal-refresh.sh."""
    now = datetime.now()
    events = []
    try:
        with open(AGENDA_FILE, newline="") as f:
            for row in csv.DictReader(f, delimiter="\t"):
                try:
                    start = datetime.strptime(f"{row['start_date']} {row['start_time'] or '00:00'}",
                                              "%Y-%m-%d %H:%M")
                    end = datetime.strptime(f"{row['end_date'] or row['start_date']} "
                                            f"{row['end_time'] or '00:00'}", "%Y-%m-%d %H:%M")
                except (KeyError, ValueError):
                    continue
                if end > now or (not row["end_time"] and start.date() == now.date()):
                    events.append((start, bool(row["start_time"]), row))
    except OSError:
        return []
    events.sort(key=lambda e: e[0])
    return events[:limit]


def when(start, timed):
    today = datetime.now().date()
    days = (start.date() - today).days
    day = "Today" if days <= 0 else "Tomorrow" if days == 1 else start.strftime("%a %d %b")
    return f"{day} {start:%H:%M}" if timed else f"{day} · all day"


# ---------- Navigable items ----------
# The panel keeps a cursor per column over rows of items and highlights the
# current item's widget with the "selected" CSS class.

class Item:
    widget = None

    def activate(self):
        pass

    def secondary(self):
        pass

    def left(self, fine=False):
        return False  # False: not handled, move the cursor instead

    def right(self, fine=False):
        return False


class Tile(Item):
    """Quick toggle: icon, title and a status line. view(state) returns
    (icon, status, active); primary/secondary run in a worker thread."""

    def __init__(self, panel, title, view, primary, secondary=None):
        self.panel, self.view = panel, view
        self.primary, self.secondary_action = primary, secondary
        self.widget = Gtk.Button(can_focus=False, hexpand=True)
        add_class(self.widget, "tile")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        self.icon = label(css="tile-icon")
        self.status = label(css="tile-status", ellipsize=Pango.EllipsizeMode.END,
                            max_width_chars=12)
        box.pack_start(self.icon, False, False, 0)
        box.pack_start(label(title, "tile-title", ellipsize=Pango.EllipsizeMode.END,
                             max_width_chars=12), False, False, 0)
        box.pack_start(self.status, False, False, 0)
        self.widget.add(box)
        self.widget.connect("clicked", lambda *_: self.activate())
        self.widget.connect("button-press-event", self.on_button)

    def on_button(self, _w, event):
        if event.button == 3:
            self.secondary()
            return True
        return False

    def update(self, state):
        icon, status, active = self.view(state)
        self.icon.set_text(icon)
        self.status.set_text(status)
        set_class(self.widget, "active", active)

    def activate(self):
        self.panel.do(self.primary)

    def secondary(self):
        if self.secondary_action:
            self.panel.hide()
            self.panel.do(self.secondary_action)


class Slider(Item):
    """Icon + scale + value. h/l adjusts, Enter runs on_activate (mute).
    apply() is debounced so holding a key doesn't spawn a command per step."""

    def __init__(self, panel, icon, lo, hi, step, fine, fmt, apply,
                 on_activate=None, delay=60, inverted=False):
        self.panel = panel
        self.step, self.fine, self.fmt = step, fine, fmt
        self.apply, self.on_activate, self.delay = apply, on_activate, delay
        self.direction = -1 if inverted else 1
        self.pending = None
        self.muted = False
        self.widget = Gtk.Box(spacing=10)
        add_class(self.widget, "slider-row")
        self.icon = label(icon, "slider-icon")
        self.adj = Gtk.Adjustment(lower=lo, upper=hi, step_increment=fine)
        self.scale = Gtk.Scale(adjustment=self.adj, draw_value=False,
                               can_focus=False, hexpand=True, inverted=inverted)
        self.value = label(css="slider-value", xalign=1.0, width_chars=6)
        self.handler = self.adj.connect("value-changed", self.on_changed)
        self.widget.pack_start(self.icon, False, False, 0)
        self.widget.pack_start(self.scale, True, True, 0)
        self.widget.pack_start(self.value, False, False, 0)

    def update(self, value, icon=None, muted=False):
        if icon:
            self.icon.set_text(icon)
        self.muted = muted
        set_class(self.widget, "muted", muted)
        if self.pending or value is None:
            return  # don't fight a value the user is still adjusting
        with self.adj.handler_block(self.handler):
            self.adj.set_value(value)
        self.show_value()

    def show_value(self):
        self.value.set_text("muted" if self.muted else self.fmt(self.adj.get_value()))

    def on_changed(self, _adj):
        self.show_value()
        if self.pending:
            GLib.source_remove(self.pending)
        self.pending = GLib.timeout_add(self.delay, self.commit)

    def commit(self):
        self.pending = None
        value = int(round(self.adj.get_value()))
        self.panel.do(lambda: self.apply(value))
        return False

    def nudge(self, sign, fine):
        step = self.fine if fine else self.step
        self.adj.set_value(self.adj.get_value() + sign * self.direction * step)
        return True

    def left(self, fine=False):
        return self.nudge(-1, fine)

    def right(self, fine=False):
        return self.nudge(+1, fine)

    def activate(self):
        if self.on_activate:
            self.panel.do(self.on_activate)


class Button(Item):
    def __init__(self, text, action, css=None):
        self.action = action
        self.widget = Gtk.Button(label=text, can_focus=False)
        if css:
            add_class(self.widget, css)
        self.widget.connect("clicked", lambda *_: self.activate())

    def activate(self):
        self.action()


class Event(Item):
    def __init__(self, panel, start, timed, row):
        self.panel, self.link = panel, row.get("hangout_link") or row.get("html_link")
        self.widget = Gtk.Button(can_focus=False)
        add_class(self.widget, "event")
        box = Gtk.Box(spacing=10)
        box.pack_start(label(when(start, timed), "event-when", width_chars=17), False, False, 0)
        box.pack_start(label(row.get("title") or "(no title)", "event-title",
                             ellipsize=Pango.EllipsizeMode.END), True, True, 0)
        self.widget.add(box)
        self.widget.connect("clicked", lambda *_: self.activate())

    def activate(self):
        if self.link:
            self.panel.hide()
            spawn("xdg-open", self.link)


class Notification(Item):
    def __init__(self, entry, dismiss):
        self.entry, self.dismiss = entry, dismiss
        self.widget = Gtk.Button(can_focus=False)
        add_class(self.widget, "notif")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        head = Gtk.Box(spacing=6)
        head.pack_start(label(entry.get("app") or "?", "notif-app"), True, True, 0)
        head.pack_start(label(ago(entry.get("time", 0)), "notif-time", xalign=1.0), False, False, 0)
        box.pack_start(head, False, False, 0)
        if entry.get("summary"):
            box.pack_start(label(entry["summary"], "notif-summary", wrap=True,
                                 wrap_mode=Pango.WrapMode.WORD_CHAR, max_width_chars=40),
                           False, False, 0)
        if entry.get("body"):
            body = label(entry["body"], "notif-body", wrap=True, lines=3,
                         wrap_mode=Pango.WrapMode.WORD_CHAR, max_width_chars=40,
                         ellipsize=Pango.EllipsizeMode.END)
            box.pack_start(body, False, False, 0)
        self.widget.add(box)
        self.widget.connect("clicked", lambda *_: self.activate())

    def activate(self):
        self.dismiss(self.entry)


# ---------- Tile views and actions ----------

def wifi_view(s):
    on, ssid = s["wifi"]
    return ("󰤨" if on else "󰤭"), (ssid or "Not connected") if on else "Off", on and bool(ssid)


def wifi_toggle():
    run("nmcli", "radio", "wifi", "off" if run("nmcli", "radio", "wifi") == "enabled" else "on")


def bt_view(s):
    on, devices = s["bt"]
    if not on:
        return "󰂲", "Off", False
    return ("󰂱" if devices else "󰂯"), (", ".join(devices) or "No devices"), bool(devices)


def bt_toggle():
    on = "Powered: yes" in run("bluetoothctl", "show")
    run("bluetoothctl", "power", "off" if on else "on")


def night_view(s):
    on, temp = s["night"]
    return ("󰖔" if on else "󰖨"), (f"{temp}K" if on else "Off"), on


def dnd_view(s):
    return ("󰂛" if s["dnd"] else "󰂚"), ("On" if s["dnd"] else "Off"), s["dnd"]


def dnd_toggle():
    run("makoctl", "mode", "-t", "do-not-disturb")
    signal_waybar()


def focus_view(s):
    left = s["focus"]
    return "󰀠", (f"{left}m left" if left is not None else "25 min"), left is not None


def caffeine_view(s):
    return ("󰅶" if s["caffeine"] else "󰛊"), ("Awake" if s["caffeine"] else "Off"), s["caffeine"]


PROFILE_ICONS = {"power-saver": "󰌪", "balanced": "󰗑", "performance": "󰓅"}


def profile_view(s):
    p = s["profile"]
    if not p:
        return "󰗑", "Unavailable", False
    return PROFILE_ICONS.get(p, "󰗑"), p.replace("-", " ").capitalize(), p != "balanced"


def profile_cycle():
    current = run("powerprofilesctl", "get")
    nxt = POWER_PROFILES[(POWER_PROFILES.index(current) + 1) % 3] if current in POWER_PROFILES else "balanced"
    run("powerprofilesctl", "set", nxt)


def layout_view(s):
    # "English (Dvorak)" -> "Dvorak"
    name = s["layout"]
    if "(" in name:
        name = name[name.index("(") + 1:].rstrip(")")
    return "󰌌", name, False


def volume_icon(pct, muted):
    if muted:
        return "󰝟"
    return "󰕿" if pct < 34 else "󰖀" if pct < 67 else "󰕾"


# ---------- Panel ----------

class ControlCenter(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.win = None
        self.cols = [[], []]      # rows of items per column
        self.cursor = [0, 0]      # remembered row per column
        self.col = self.c = 0
        self.selected = None
        self.ticker = None
        self.shown_at = 0.0
        self.reading = False
        self.history_mtime = None
        self.agenda_mtime = None
        self.media_visible = False
        self.net_last = None
        self.notifs = []
        self.events = []

    def do_startup(self):
        Gtk.Application.do_startup(self)
        self.hold()  # stay resident while hidden
        css = Gtk.CssProvider()
        css.load_from_path(os.path.join(HERE, "style.css"))
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_USER)
        psutil.cpu_percent(None)  # prime the first sample
        self.build()

    def do_activate(self):
        if self.win.get_visible():
            # Ignore a second activation right after opening (double-fired
            # bind or key repeat), which would close the panel instantly.
            if time.monotonic() - self.shown_at > 0.4:
                self.hide()
        else:
            self.show()

    # --- construction ---

    def build(self):
        win = self.win = Gtk.ApplicationWindow(application=self, title="Control center")
        win.set_resizable(False)
        win.set_decorated(False)
        visual = win.get_screen().get_rgba_visual()
        if visual:
            win.set_visual(visual)
            win.set_app_paintable(True)
        if GtkLayerShell:
            GtkLayerShell.init_for_window(win)
            GtkLayerShell.set_namespace(win, "control-center")
            GtkLayerShell.set_layer(win, GtkLayerShell.Layer.OVERLAY)
            GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.TOP, True)
            GtkLayerShell.set_margin(win, GtkLayerShell.Edge.TOP, 6)
            GtkLayerShell.set_keyboard_mode(win, GtkLayerShell.KeyboardMode.EXCLUSIVE)
        else:
            win.connect("focus-out-event", lambda *_: self.hide())
        win.connect("key-press-event", self.on_key)
        win.connect("delete-event", lambda *_: self.hide() or True)

        panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        add_class(panel, "panel")
        win.add(panel)
        columns = Gtk.Box(spacing=16)
        panel.pack_start(columns, True, True, 0)
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, width_request=480)
        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, width_request=400)
        columns.pack_start(left, False, False, 0)
        columns.pack_start(right, False, False, 0)

        # Left: tiles, sliders, media.
        self.tiles = [
            Tile(self, "Wi-Fi", wifi_view, wifi_toggle,
                 lambda: spawn(os.path.join(WOFI_SCRIPTS, "wifi-picker.sh"))),
            Tile(self, "Bluetooth", bt_view, bt_toggle,
                 lambda: spawn(os.path.join(WOFI_SCRIPTS, "bluetooth-picker.sh"))),
            Tile(self, "Night", night_view, lambda: run(f"{BIN}/nightlight", "toggle")),
            Tile(self, "Silence", dnd_view, dnd_toggle),
            Tile(self, "Focus", focus_view, lambda: run(f"{BIN}/focus-mode", "toggle")),
            Tile(self, "Caffeine", caffeine_view, lambda: run(f"{BIN}/caffeine", "toggle")),
            Tile(self, "Power", profile_view, profile_cycle),
            Tile(self, "Keyboard", layout_view,
                 lambda: run("niri", "msg", "action", "switch-layout", "next")),
        ]
        tile_grid = Gtk.Grid(column_spacing=8, row_spacing=8, column_homogeneous=True)
        for i, t in enumerate(self.tiles):
            tile_grid.attach(t.widget, i % 4, i // 4, 1, 1)
        left.pack_start(tile_grid, False, False, 0)

        self.brightness = Slider(
            self, "󰃟", 1, 100, 5, 1, lambda v: f"{v:.0f}%",
            lambda v: run("brightnessctl", "--class=backlight", "-q", "set", f"{v}%"))
        # Right = warmer, so the scale is inverted (lower kelvin to the right).
        self.warmth = Slider(
            self, "󰖔", 2500, 6000, 250, 50, lambda v: f"{v:.0f}K",
            lambda v: run(f"{BIN}/nightlight", "temp", str(v)), delay=400, inverted=True)
        self.volume = Slider(
            self, "󰕾", 0, 100, 5, 1, lambda v: f"{v:.0f}%",
            lambda v: run("wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{v}%"),
            lambda: run("wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"))
        self.mic = Slider(
            self, "󰍬", 0, 100, 5, 1, lambda v: f"{v:.0f}%",
            lambda v: run("wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", f"{v}%"),
            lambda: run("wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"))
        self.sliders = [self.brightness, self.warmth, self.volume, self.mic]
        for s in self.sliders:
            left.pack_start(s.widget, False, False, 0)

        self.media = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, no_show_all=True)
        add_class(self.media, "media")
        self.media_title = label(css="media-title", ellipsize=Pango.EllipsizeMode.END)
        self.media_artist = label(css="media-artist", ellipsize=Pango.EllipsizeMode.END)
        controls = Gtk.Box(spacing=8, homogeneous=True)
        self.media_buttons = [
            Button("󰒮", lambda: self.do(lambda: run("playerctl", "previous")), "media-button"),
            Button("󰐊", lambda: self.do(lambda: run("playerctl", "play-pause")), "media-button"),
            Button("󰒭", lambda: self.do(lambda: run("playerctl", "next")), "media-button"),
        ]
        for b in self.media_buttons:
            controls.pack_start(b.widget, True, True, 0)
        for w in (self.media_title, self.media_artist, controls):
            self.media.pack_start(w, False, False, 0)
            w.show_all()
        left.pack_start(self.media, False, False, 0)

        # Right: stats, calendar, notifications.
        right.pack_start(self.build_stats(), False, False, 0)

        right.pack_start(label("Calendar", "section-title"), False, False, 0)
        self.event_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        right.pack_start(self.event_box, False, False, 0)

        head = Gtk.Box(spacing=8)
        head.pack_start(label("Notifications", "section-title"), True, True, 0)
        self.clear_btn = Button("󰎟  Clear all", self.clear_all, "clear-all")
        head.pack_start(self.clear_btn.widget, False, False, 0)
        right.pack_start(head, False, False, 0)

        self.notif_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.scroller.set_propagate_natural_height(True)
        self.scroller.set_max_content_height(300)
        self.scroller.add(self.notif_box)
        right.pack_start(self.scroller, False, False, 0)

        panel.pack_start(label(
            "j/k move · h/l adjust · Tab column · ⏎ toggle · o open · x dismiss · D clear all · q close",
            "hint", xalign=0.5), False, False, 0)

        panel.show_all()

    def build_stats(self):
        grid = Gtk.Grid(column_spacing=10, row_spacing=6)
        add_class(grid, "stats")
        self.stats = {}
        for i, (key, icon, name) in enumerate((
                ("cpu", "", "CPU"), ("ram", "\U000f035b", "RAM"),
                ("disk", "\U000f02ca", "Disk"), ("net", "\U000f04e1", "Net"))):
            grid.attach(label(f"{icon}  {name}", "stat-name"), 0, i, 1, 1)
            bar = None
            if key != "net":
                bar = Gtk.ProgressBar(hexpand=True, valign=Gtk.Align.CENTER)
                grid.attach(bar, 1, i, 1, 1)
            value = label(css="stat-value", xalign=1.0)
            # Net has no bar, so its text spans both columns.
            grid.attach(value, 1 if bar is None else 2, i, 2 if bar is None else 1, 1)
            self.stats[key] = (bar, value)
        return grid

    def set_stat(self, key, fraction, text):
        bar, value = self.stats[key]
        value.set_text(text)
        if bar:
            bar.set_fraction(min(max(fraction, 0.0), 1.0))
            set_class(bar, "critical", fraction >= 0.9)
            set_class(bar, "high", 0.75 <= fraction < 0.9)

    # --- background work ---

    def do(self, fn):
        """Run an action off the main thread, then refresh the state."""
        def work():
            fn()
            self.read_async()
        threading.Thread(target=work, daemon=True).start()

    def read_async(self):
        if self.reading:
            return
        self.reading = True

        def work():
            try:
                state = read_state()
            finally:
                self.reading = False
            GLib.idle_add(self.apply_state, state)
        threading.Thread(target=work, daemon=True).start()

    def apply_state(self, s):
        for t in self.tiles:
            t.update(s)
        self.brightness.update(s["brightness"])
        self.warmth.update(s["night"][1])
        if s["volume"]:
            self.volume.update(s["volume"][0], volume_icon(*s["volume"]), s["volume"][1])
        if s["mic"]:
            self.mic.update(s["mic"][0], "󰍭" if s["mic"][1] else "󰍬", s["mic"][1])
        media = s["media"]
        if media:
            self.media_title.set_text(media["title"] or media["player"])
            self.media_artist.set_text(" · ".join(x for x in (media["artist"], media["player"]) if x))
            self.media_buttons[1].widget.set_label("󰏤" if media["status"] == "Playing" else "󰐊")
        if bool(media) != self.media_visible:
            self.media_visible = bool(media)
            self.media.set_visible(self.media_visible)
            self.rebuild_rows()
        return False

    # --- refresh ---

    def refresh_stats(self):
        cpu = psutil.cpu_percent(None)
        load = os.getloadavg()[0]
        self.set_stat("cpu", cpu / 100, f"{cpu:.0f}% · load {load:.2f}")
        mem = psutil.virtual_memory()
        self.set_stat("ram", mem.percent / 100,
                      f"{human_bytes(mem.used)} / {human_bytes(mem.total)}")
        disk = psutil.disk_usage("/")
        self.set_stat("disk", disk.percent / 100,
                      f"{human_bytes(disk.used)} / {human_bytes(disk.total)}")
        io = psutil.net_io_counters(pernic=True)
        recv = sum(v.bytes_recv for k, v in io.items() if k != "lo")
        sent = sum(v.bytes_sent for k, v in io.items() if k != "lo")
        now = time.monotonic()
        down = up = 0.0
        if self.net_last:
            r0, s0, t0 = self.net_last
            dt = max(now - t0, 1e-3)
            down, up = (recv - r0) / dt, (sent - s0) / dt
        self.net_last = (recv, sent, now)
        self.set_stat("net", 0, f"↓ {human_bytes(down)}/s   ↑ {human_bytes(up)}/s")

    def refresh_agenda(self, force=False):
        try:
            mtime = os.stat(AGENDA_FILE).st_mtime
        except OSError:
            mtime = None
        if not force and mtime == self.agenda_mtime:
            return
        self.agenda_mtime = mtime
        for child in self.event_box.get_children():
            child.destroy()
        self.events = [Event(self, *e) for e in read_agenda()]
        for e in self.events:
            self.event_box.pack_start(e.widget, False, False, 0)
        if not self.events:
            self.event_box.pack_start(label("No upcoming events", "empty", xalign=0.5),
                                      False, False, 0)
        self.event_box.show_all()
        self.rebuild_rows()

    def refresh_notifications(self, force=False):
        try:
            mtime = os.stat(HISTORY_FILE).st_mtime
        except OSError:
            mtime = None
        if not force and mtime == self.history_mtime:
            return
        self.history_mtime = mtime
        for child in self.notif_box.get_children():
            child.destroy()
        self.notifs = [Notification(e, self.dismiss) for e in read_history()]
        for n in self.notifs:
            self.notif_box.pack_start(n.widget, False, False, 0)
        if not self.notifs:
            self.notif_box.pack_start(label("No notifications", "empty", xalign=0.5),
                                      False, False, 0)
        self.notif_box.show_all()
        self.clear_btn.widget.set_sensitive(bool(self.notifs))
        self.rebuild_rows()

    def rebuild_rows(self):
        left = [self.tiles[:4], self.tiles[4:]] + [[s] for s in self.sliders]
        if self.media_visible:
            left.append(self.media_buttons)
        right = [[e] for e in self.events] + [[self.clear_btn]] + [[n] for n in self.notifs]
        self.cols = [left, right]
        self.select(self.col, self.cursor[self.col], self.c)

    def tick(self):
        self.read_async()
        self.refresh_stats()
        self.refresh_agenda()
        self.refresh_notifications()
        return True

    # --- show / hide ---

    def show(self):
        self.col = self.c = 0
        self.cursor = [0, 0]
        self.refresh_agenda(force=True)
        self.refresh_notifications(force=True)
        self.tick()
        self.shown_at = time.monotonic()
        self.win.show()
        self.win.present()
        self.ticker = GLib.timeout_add_seconds(1, self.tick)
        # Opening the panel marks all notifications as viewed.
        with open(SEEN_FILE, "w") as f:
            f.write(f"{int(time.time())}\n")
        signal_waybar()

    def hide(self):
        if self.ticker:
            GLib.source_remove(self.ticker)
            self.ticker = None
        self.win.hide()

    # --- notifications ---

    def dismiss(self, entry):
        target = json.dumps(entry)
        try:
            with open(HISTORY_FILE) as f:
                lines = f.read().splitlines()
        except OSError:
            return
        # Drop the newest matching line only (identical entries can repeat).
        for i in range(len(lines) - 1, -1, -1):
            try:
                if json.dumps(json.loads(lines[i])) == target:
                    del lines[i]
                    break
            except ValueError:
                continue
        with open(HISTORY_FILE, "w") as f:
            f.write("".join(line + "\n" for line in lines))
        self.refresh_notifications(force=True)
        signal_waybar()

    def clear_all(self):
        run("makoctl", "dismiss", "-a")
        open(HISTORY_FILE, "w").close()
        self.refresh_notifications(force=True)
        signal_waybar()

    # --- keyboard navigation ---

    def rows(self):
        return self.cols[self.col]

    def current(self):
        try:
            return self.rows()[self.cursor[self.col]][self.c]
        except IndexError:
            return None

    def select(self, col, r, c):
        if self.selected:
            set_class(self.selected, "selected", False)
        if not self.cols[col]:
            col = 1 - col
        self.col = col
        rows = self.rows()
        r = max(0, min(r, len(rows) - 1))
        self.cursor[col] = r
        self.c = max(0, min(c, len(rows[r]) - 1))
        item = self.current()
        self.selected = item.widget
        set_class(self.selected, "selected", True)
        if isinstance(item, Notification):
            GLib.idle_add(self.scroll_to, item.widget)

    def switch_column(self, to_end=False):
        col = 1 - self.col
        rows = self.cols[col]
        c = len(rows[self.cursor[col]]) - 1 if to_end and rows else 0
        self.select(col, self.cursor[col], c)

    def scroll_to(self, widget):
        alloc = widget.get_allocation()
        adj = self.scroller.get_vadjustment()
        top, bottom = adj.get_value(), adj.get_value() + adj.get_page_size()
        if alloc.y < top:
            adj.set_value(alloc.y)
        elif alloc.y + alloc.height > bottom:
            adj.set_value(alloc.y + alloc.height - adj.get_page_size())
        return False

    def on_key(self, _win, event):
        key = Gdk.keyval_name(event.keyval)
        ctrl = event.state & Gdk.ModifierType.CONTROL_MASK
        item = self.current()
        r = self.cursor[self.col]
        row_len = len(self.rows()[r])
        if key in ("Escape", "q"):
            self.hide()
        elif ctrl and key == "d":
            self.select(self.col, r + 5, self.c)
        elif ctrl and key == "u":
            self.select(self.col, r - 5, self.c)
        elif key in ("j", "Down"):
            self.select(self.col, r + 1, self.c)
        elif key in ("k", "Up"):
            self.select(self.col, r - 1, self.c)
        elif key in ("h", "H", "Left"):
            if not item.left(fine=key == "H"):
                if self.c == 0 and self.col == 1:
                    self.switch_column(to_end=True)
                else:
                    self.select(self.col, r, self.c - 1)
        elif key in ("l", "L", "Right"):
            if not item.right(fine=key == "L"):
                if self.c == row_len - 1 and self.col == 0:
                    self.switch_column()
                else:
                    self.select(self.col, r, self.c + 1)
        elif key in ("Tab", "ISO_Left_Tab"):
            self.switch_column()
        elif key == "g":
            self.select(self.col, 0, 0)
        elif key == "G":
            self.select(self.col, len(self.rows()) - 1, 0)
        elif key in ("Return", "KP_Enter", "space"):
            item.activate()
        elif key == "o":
            item.secondary()
        elif key == "x" and isinstance(item, Notification):
            item.activate()
        elif key == "D":
            self.clear_all()
        elif key == "n":
            self.tiles[2].activate()
        else:
            return False
        return True


if __name__ == "__main__":
    # Wayland app-id; matched by the niri window-rule.
    GLib.set_prgname("control-center")
    sys.exit(ControlCenter().run(sys.argv))
