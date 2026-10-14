#!/bin/bash
# Coppernight one-command installer for Omarchy.
#
#   curl -fsSL https://raw.githubusercontent.com/Mehdi-Samardan/omarchy-theme/main/install.sh | bash
#
# or from a clone:  ./install.sh
#
# Installs the theme, the Hyprland look'n'feel (rounding, blur, shadow,
# smooth animations) and the Hyprland Tweaks bar widget. Every file it
# replaces is backed up next to the original as <file>.bak.<timestamp>.
set -euo pipefail

REPO_URL="https://github.com/Mehdi-Samardan/omarchy-theme.git"
THEME_NAME="coppernight"
PLUGIN_ID="mehdi.hyprtweaks"
STAMP=$(date +%s)

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
THEME_DIR="$CONFIG/omarchy/themes/$THEME_NAME"
PLUGIN_DIR="$CONFIG/omarchy/plugins/$PLUGIN_ID"
SHELL_JSON="$CONFIG/omarchy/shell.json"
LOOKNFEEL="$CONFIG/hypr/looknfeel.lua"

step() { echo "→ $1"; }
ok()   { echo "  ✓ $1"; }

backup() {
  if [ -e "$1" ]; then
    cp -a "$1" "$1.bak.$STAMP"
    ok "backed up $(basename "$1") → $(basename "$1").bak.$STAMP"
  fi
}

command -v omarchy >/dev/null 2>&1 || { echo "Omarchy not found — this installer is for Omarchy systems." >&2; exit 1; }

# When piped through curl there is no repo on disk yet: clone it.
SRC=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/colors.toml" ]; then
  SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  SRC=$(mktemp -d)
  trap 'rm -rf "$SRC"' EXIT
  step "Downloading Coppernight"
  git clone --depth 1 --quiet "$REPO_URL" "$SRC"
  ok "cloned $REPO_URL"
fi

# 1. Theme
step "Installing theme to $THEME_DIR"
mkdir -p "$THEME_DIR"
tar -C "$SRC" --exclude=.git --exclude=extras --exclude=install.sh -cf - . | tar -C "$THEME_DIR" -xf -
ok "theme files copied"

# 2. Hyprland look'n'feel
step "Installing Hyprland look'n'feel"
mkdir -p "$(dirname "$LOOKNFEEL")"
backup "$LOOKNFEEL"
cp "$SRC/extras/hypr/looknfeel.lua" "$LOOKNFEEL"
ok "rounding 8, border 1, shadow, blur and smooth animations"

# 3. Hyprland Tweaks bar widget
step "Installing Hyprland Tweaks bar widget"
mkdir -p "$PLUGIN_DIR"
cp "$SRC/extras/omarchy/plugins/$PLUGIN_ID/"* "$PLUGIN_DIR/"
ok "plugin copied to $PLUGIN_DIR"

if [ ! -f "$SHELL_JSON" ]; then
  cp "${OMARCHY_PATH:-/usr/share/omarchy}/config/omarchy/shell.json" "$SHELL_JSON"
else
  backup "$SHELL_JSON"
fi
python3 - "$SHELL_JSON" "$PLUGIN_ID" <<'EOF'
import json, sys
path, plugin = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
right = data.setdefault("bar", {}).setdefault("layout", {}).setdefault("right", [])
if not any(item.get("id") == plugin for item in right):
    right.append({"id": plugin})
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
EOF
ok "widget added to the top-right of the bar"

# 4. Apply
step "Applying"
omarchy theme set "$THEME_NAME" >/dev/null 2>&1 || omarchy-theme-set "$THEME_NAME"
ok "theme set to $THEME_NAME"
hyprctl reload >/dev/null 2>&1 && ok "Hyprland reloaded" || true
omarchy restart shell >/dev/null 2>&1 && ok "shell restarted" || true

echo
echo "Done! Click the Hyprland logo in the top-right of the bar to tweak everything live."
echo "Optional extras (need sudo): $THEME_DIR/apply-icons.sh and $THEME_DIR/apply-filemanager.sh"
