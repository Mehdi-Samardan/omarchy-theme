# 🎨 Omarchy Theme

A minimalist, elegant theme designed for digital minimalists. Inspired by Black Arch aesthetics, Omarchy provides a cohesive visual experience across your entire Linux desktop environment.

## ✨ Features

- **🎯 Unified Design**: Consistent color scheme across all applications for seamless visual continuity
- **✂️ Minimal & Clean**: Distraction-free interface with purposeful design philosophy
- **🔄 Wide Compatibility**: Supports 20+ desktop environments, terminal emulators, and applications
- **🌙 Dark Theme**: Carefully crafted dark palette, easy on the eyes for extended work sessions
- **⚡ Performance Optimized**: Lightweight configurations with no unnecessary animations
- **🎨 Color Harmony**: Scientifically balanced color palette inspired by minimalist principles
- **🔧 Highly Customizable**: Easy-to-modify configs for personalization without breaking consistency
- **📱 Cross-Platform Ready**: Works seamlessly across different Linux distributions

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

### Prerequisites

- Linux distribution with X11 or Wayland support
- Git (for cloning the repository)
- Configuration directories already exist on your system

### Automated Installation

Use the provided installation command:

```bash
omarchy-theme-install
```

### Manual Installation

Clone the repository and copy files:

```bash
# Clone the repository
git clone https://github.com/Mehdi-Samardan/omarchy-theme.git

# Copy individual configs as needed
cp omarchy-theme/kitty.conf ~/.config/kitty/
cp omarchy-theme/hyprland.conf ~/.config/hypr/
cp omarchy-theme/gtk.css ~/.config/gtk-3.0/
cp omarchy-theme/alacritty.toml ~/.config/alacritty/
```

### Quick Start

1. **Install the theme** using one of the methods above
2. **Reload your environment** (restart or source configs)
3. **Enjoy!** The theme will automatically apply to supported applications

For terminal emulators, restart the terminal. For window managers, use your reload keybinding (e.g., `$mod+Shift+R` in Hyprland).

## 🎨 Color Palette

The Omarchy theme uses a carefully selected color scheme:

- **Background**: Deep black (#000000) for minimal eye strain
- **Foreground**: Crisp white (#FFFFFF) for maximum contrast
- **Accents**: Carefully balanced secondary colors for UI elements
- **Status Colors**: Green for success, Red for errors, Yellow for warnings

This palette follows minimalist design principles while maintaining excellent readability.

## ⚙️ Configuration

Each application has its own configuration file. Refer to the individual files for customization options specific to your needs.

### Popular Customizations

- **Terminal Colors**: Edit the respective terminal config file (e.g., `kitty.conf`, `alacritty.toml`)
- **GTK Theme**: Modify `gtk.css` for application styling
- **Window Manager**: Customize `hyprland.conf` for window management behavior and animations
- **Status Bar**: Adjust `waybar.css` for taskbar appearance and layout
- **Keybindings**: Edit window manager configs to customize keybindings

### Advanced Tips

- **Custom Fonts**: Update terminal and editor configs to use your preferred fonts
- **Opacity Levels**: Adjust transparency settings in `hyprlock.conf` and `mako.ini`
- **Spacing & Gaps**: Modify window gaps and padding in `hyprland.conf`
- **Monitor Setup**: Configure multi-monitor support in `waybar.css` and `hyprland.conf`

## 🐛 Troubleshooting

### Configs Not Applied

- **Solution**: Ensure files are in the correct configuration directories (usually `~/.config/`)
- **Check permissions**: Verify files are readable (`chmod 644 file`)
- **Reload apps**: Restart applications or your session for changes to take effect

### Colors Look Wrong

- **Check terminal**: Some terminals override theme colors; check terminal settings
- **Verify file location**: Ensure config files are in the right directory
- **GTK cache**: Clear GTK cache with `rm -rf ~/.cache/gtk-3.0`

### Keyboard Shortcuts Not Working

- **Edit keybindings**: Check `hyprland.conf` or your WM config for correct mod keys
- **Mod key**: Verify your mod key setting (usually `SUPER` or `ALT`)
- **Reload config**: Restart your window manager (`$mod+Shift+R`)

### Performance Issues

- **Disable animations**: Set animation speeds to 0 in config files
- **Check GPU**: Ensure GPU drivers are properly installed
- **Reduce eyecandy**: Minimize blur and transparency effects if needed

## 📚 Documentation

For more detailed information on individual applications:

- **Hyprland**: [hyprland.fr](https://hyprland.fr)
- **Waybar**: [GitHub - waybar](https://github.com/Alexays/Waybar)
- **Neovim**: [neovim.io](https://neovim.io)
- **GTK**: [GNOME Developers](https://developer.gnome.org)

## 📝 License

This theme is provided as-is for personal and community use.

## 🤝 Contributing

Improvements, suggestions, and contributions are welcome. Feel free to open issues or pull requests to enhance the theme.

## 📞 Support

For issues, questions, or suggestions, please open an issue on the repository.
