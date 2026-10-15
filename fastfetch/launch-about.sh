#!/bin/bash
# Opens the About page (omarchy-launch-about) in foot with a smaller font so the
# whole stacked page fits on screen. Focuses it instead if it's already open.
FONT="$(omarchy-font-current 2>/dev/null || echo 'JetBrainsMono Nerd Font'):size=8"
exec omarchy-launch-or-focus org.omarchy.about \
  "setsid uwsm-app -- foot --app-id=org.omarchy.about -o font='$FONT' -e omarchy-launch-about --render"
