# 🎨 Omarchy Theme

A minimalist, elegant theme designed for digital minimalists. Inspired by Black Arch aesthetics, Omarchy provides a cohesive visual experience across your entire Linux desktop environment.

## ✨ Features

- **Unified Design**: Consistent color scheme across all applications
- **Minimal & Clean**: Distraction-free interface with purposeful design
- **Wide Compatibility**: Supports multiple desktop environments and applications
- **Dark Theme**: Easy on the eyes, perfect for extended work sessions

## 📦 Supported Applications

This theme includes configurations for:

- **Terminal Emulators**: Alacritty, Kitty, Foot, Ghostty
- **Window Managers**: Hyprland, Sway
- **System UI**: Waybar, GTK, Hyprlock, Mako
- **Editors & Tools**: Neovim, Firefox, Chromium
- **Music & Monitoring**: cava, btop
- **Notification**: swayosd
- **Shells & Utils**: Walker

## 📋 File Structure

```
├── alacritty.toml          # Alacritty terminal emulator config
├── btop.theme              # System monitoring (btop) theme
├── cava_theme              # Audio visualizer theme
├── chromium.theme          # Chromium browser theme
├── firefox.css             # Firefox browser styling
├── foot.ini                # Foot terminal emulator config
├── ghostty.conf            # Ghostty terminal emulator config
├── gtk.css                 # GTK applications theme
├── hyprland.conf           # Hyprland window manager config
├── hyprlock.conf           # Hyprlock lock screen config
├── icons.theme             # Icon theme configuration
├── kitty.conf              # Kitty terminal emulator config
├── mako.ini                # Mako notification daemon config
├── neovim.lua              # Neovim editor configuration
├── swayosd.css             # Sway on-screen display styling
├── vencord.theme.css       # Discord Vencord theme
├── vscode_colors.json      # VS Code color scheme
├── vscode.json             # VS Code settings
├── walker.css              # Walker application launcher theme
├── waybar.css              # Waybar status bar styling
└── backgrounds/            # Wallpaper collection
```

## 🚀 Installation

### Automated Installation

Use the provided installation command:

```bash
omarchy-theme-install
```

### Manual Installation

Copy the relevant configuration files to their respective locations:

```bash
# Example for Hyprland
cp hyprland.conf ~/.config/hypr/

# Example for Kitty
cp kitty.conf ~/.config/kitty/

# Example for GTK
cp gtk.css ~/.config/gtk-3.0/
```

## ⚙️ Configuration

Each application has its own configuration file. Refer to the individual files for customization options specific to your needs.

### Popular Customizations

- **Terminal Colors**: Edit the respective terminal config file (e.g., `kitty.conf`, `alacritty.toml`)
- **GTK Theme**: Modify `gtk.css` for application styling
- **Window Manager**: Customize `hyprland.conf` for window management behavior
- **Status Bar**: Adjust `waybar.css` for taskbar appearance

## 📝 License

This theme is provided as-is for personal and community use.

## 🤝 Contributing

Improvements, suggestions, and contributions are welcome. Feel free to open issues or pull requests to enhance the theme.

## 📞 Support

For issues, questions, or suggestions, please open an issue on the repository.
