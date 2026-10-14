# Coppernight

Dark Omarchy theme with deep indigo tones and copper accents. It also includes a polished Hyprland look'n'feel and a bar widget for changing Hyprland settings live.

![Coppernight preview](preview.png)

## Install (one command)

```bash
curl -fsSL https://raw.githubusercontent.com/Mehdi-Samardan/omarchy-theme/main/install.sh | bash
```

Or from a clone:

```bash
git clone https://github.com/Mehdi-Samardan/omarchy-theme.git
cd omarchy-theme
./install.sh
```

The installer:

1. Copies the theme to `~/.config/omarchy/themes/coppernight` and activates it.
2. Installs the Hyprland look'n'feel to `~/.config/hypr/looknfeel.lua`.
3. Installs the **Hyprland Tweaks** bar widget and adds it to the top-right of the bar.
4. Reloads Hyprland and restarts the Omarchy shell.

Before replacing a file, the installer saves a backup next to it as `<file>.bak.<timestamp>`.

## Features

### Theme
- GTK, Hyprland, and terminal styling (Alacritty, Kitty, Ghostty, Foot)
- Editor themes: Neovim, VS Code, Zed, Helix, Sublime, Emacs, Vim
- App themes: Firefox, Chromium, Obsidian, Vencord, btop, lazygit, yazi, tmux, starship, fastfetch
- Optional icon/cursor and file-manager setup scripts
- Included wallpapers and preview assets

### Hyprland look'n'feel
- Rounded corners (8px) with a thin 1px border
- Soft window shadows
- Blur behind translucent surfaces (bar, menus, transparent windows)
- Smooth window animations with a slight spring when windows open
- Workspaces slide when you switch

### Hyprland Tweaks bar widget
Click the Hyprland logo in the top-right of the bar to open a panel with about 90 Hyprland settings. Changes apply live.

| Section | What you can change |
|---|---|
| General | Border size, gaps, layout (dwindle / master / scrolling), resize on border, snapping, tearing |
| Colors | Active and inactive border colors, shadow color |
| Decoration | Rounding and rounding curve, active/inactive/fullscreen opacity, dimming |
| Blur | Size, passes, noise, contrast, brightness, vibrancy, xray, popups |
| Shadow | Range, falloff, scale, sharpness |
| Animations | Window and workspace styles, animation speeds |
| Input | Mouse sensitivity and acceleration, focus follows mouse, scroll speed, key repeat, touchpad |
| Cursor | Screen zoom, hide when idle, cursor warping |
| Layouts | Dwindle, master and scrolling layout options |
| Groups | Group bar |
| Misc & Performance | VRR, direct scanout, terminal swallowing, wake-on-input |

- Type in the search box to find a setting.
- Settings you changed are highlighted. Click ↺, or right-click a slider, to reset one setting. **Reset all** undoes every change.
- Only the settings you change are saved, to `~/.config/hypr/tweaks.lua`, so they survive reboots.

## Optional extras

```bash
cd ~/.config/omarchy/themes/coppernight
./apply-icons.sh        # Papirus-Dark with orange folders + peach cursor
./apply-filemanager.sh  # File manager styling
```

## Undo

```bash
cd ~/.config/omarchy/themes/coppernight
./remove-gtk.sh
./remove-icons.sh
```

- **Look'n'feel:** restore `~/.config/hypr/looknfeel.lua.bak.<timestamp>`.
- **Bar widget:** delete `~/.config/omarchy/plugins/mehdi.hyprtweaks`, then remove `mehdi.hyprtweaks` from `~/.config/omarchy/shell.json`.
- **Saved widget settings:** delete `~/.config/hypr/tweaks.lua`.

## Repository layout

```
.                      Theme files (copied to ~/.config/omarchy/themes/coppernight)
extras/hypr/           Hyprland look'n'feel
extras/omarchy/plugins Hyprland Tweaks bar widget
install.sh             One-command installer
```
