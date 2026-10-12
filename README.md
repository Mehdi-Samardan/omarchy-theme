# Coppernight

A dark, high-contrast theme pack for Omarchy with deep indigo surfaces, copper accents, and a warm neon glow. It is designed to feel modern and cinematic while staying readable in everyday desktop use.

This repository contains the Coppernight theme assets and related configuration snippets for a wide range of tools, including:

- Hyprland/Omarchy shell surfaces
- GTK and file manager styling
- Terminal themes (Alacritty, Kitty, Ghostty, Foot, etc.)
- Editor themes for Neovim, Helix, VS Code, Zed, and more
- Firefox userChrome styling
- Discord/Vencord, Obsidian, and other app customizations
- Icon and cursor helpers for a consistent desktop look

## Preview

The theme focuses on a deep charcoal-indigo base with copper highlights and soft glow accents. It is especially suited for dark desktop setups and low-light coding sessions.

## Repository structure

- `colors.toml` — core palette values
- `shell.toml` — Omarchy shell theme configuration
- `gtk.css` — GTK styling
- `firefox-userChrome.css` — Firefox customization
- `apply-filemanager.sh` — applies file manager styling and Yazi flavor
- `apply-icons.sh` — configures Papirus icons and copper/orange folder accents
- `remove-gtk.sh` / `remove-icons.sh` — restores defaults
- `*.toml`, `*.conf`, `*.json`, `*.theme`, `*.css`, `*.lua` — app-specific theme files
- `backgrounds/` — included wallpaper/background images
- `preview.png` — sample preview image

## Installation

This repository is intended to be used as an Omarchy theme pack. The usual setup is to place the theme in your Omarchy theme directory and apply it through Omarchy.

### 1) Copy the theme into Omarchy

```bash
mkdir -p ~/.config/omarchy/themes
cp -r /path/to/omarchy-theme ~/.config/omarchy/themes/coppernight
```

If you already cloned the repository locally, use your own path instead of `/path/to/omarchy-theme`.

### 2) Apply the theme

```bash
omarchy theme set coppernight
```

### 3) Apply optional desktop tweaks

The repository includes helper scripts for file manager and icon styling.

```bash
cd ~/.config/omarchy/themes/coppernight
./apply-filemanager.sh
./apply-icons.sh
```

These scripts help with:

- GTK file manager background styling
- Yazi theme flavor setup
- Papirus icon theme
- Orange folder accenting
- Peach cursor theme

## Removal / restore defaults

If you want to undo the extra file manager or icon customization:

```bash
cd ~/.config/omarchy/themes/coppernight
./remove-gtk.sh
./remove-icons.sh
```

## Notes

- Some pieces are intended to work best inside an Omarchy-based environment.
- Some packages may need to be installed via `omarchy pkg` or your distro package manager.
- If an app-specific config is not automatically applied, you can still copy the included config files into that app's config directory manually.

## License

This project is distributed without an explicit license file in the repository. Please check the repository owner or upstream project for licensing details before redistributing or reusing it commercially.

## Credits

Built for Omarchy users who want a cohesive, dark, copper-accented desktop experience. The theme includes app-specific styling contributed to fit the same visual language across the system.
