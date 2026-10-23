#!/usr/bin/env python3
# Eavesdrops on org.freedesktop.Notifications.Notify calls on the session
# bus and appends summary/body to a JSONL history file, since mako's own
# IPC (makoctl history) only exposes app name + urgency, not the message
# text. Used by waybar/scripts/notifications-menu.sh to show a history
# menu, since mako itself has no history panel (unlike e.g. swaync).

import json
import os
import subprocess
import time

import dbus
import dbus.mainloop.glib
from dbus.lowlevel import HANDLER_RESULT_HANDLED, HANDLER_RESULT_NOT_YET_HANDLED
from gi.repository import GLib

HISTORY_FILE = os.path.expanduser("~/.cache/mako-notif-history.jsonl")
MAX_ENTRIES = 50

# Must match the "signal" set on custom/notifications in waybar/config.jsonc.
WAYBAR_SIGNAL = "RTMIN+9"


def append_entry(entry):
    lines = []
    if os.path.exists(HISTORY_FILE):
        with open(HISTORY_FILE) as f:
            lines = f.read().splitlines()
    lines.append(json.dumps(entry))
    lines = lines[-MAX_ENTRIES:]
    os.makedirs(os.path.dirname(HISTORY_FILE), exist_ok=True)
    with open(HISTORY_FILE, "w") as f:
        f.write("\n".join(lines) + "\n")
    subprocess.run(["pkill", "-" + WAYBAR_SIGNAL, "waybar"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def on_message(bus, message):
    if (
        message.get_interface() != "org.freedesktop.Notifications"
        or message.get_member() != "Notify"
    ):
        return HANDLER_RESULT_NOT_YET_HANDLED
    args = message.get_args_list()
    if len(args) >= 7:
        app_name, _replaces_id, _app_icon, summary, body, _actions, hints = args[:7]
        # Volume/brightness pop-ups and transient notices (notify-send -e)
        # aren't worth keeping in the history.
        if str(app_name) != "osd" and not bool(hints.get("transient", False)):
            append_entry(
                {
                    "time": int(time.time()),
                    "app": str(app_name),
                    "summary": str(summary),
                    "body": str(body),
                }
            )
    # The eavesdropped call isn't addressed to us. Marking it handled stops
    # libdbus from auto-replying "UnknownMethod" to the sender, which raced
    # mako's real reply (notify-send -p would sometimes get the error).
    return HANDLER_RESULT_HANDLED


dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
bus.add_match_string_non_blocking(
    "eavesdrop=true,type='method_call',"
    "interface='org.freedesktop.Notifications',member='Notify'"
)
bus.add_message_filter(on_message)

GLib.MainLoop().run()
