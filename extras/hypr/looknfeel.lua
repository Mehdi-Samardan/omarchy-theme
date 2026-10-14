-- Coppernight look'n'feel overrides (installed to ~/.config/hypr/looknfeel.lua).
-- Loaded after Omarchy's defaults and the theme, so these values win.

local home = os.getenv("HOME")

hl.config({
  general = {
    gaps_in = 0,
    gaps_out = 0,
    border_size = 1,
    col = {
      active_border = "rgba(b0b0b0ff)",
      inactive_border = "rgba(404040ff)",
    },
  },

  decoration = {
    rounding = 8,

    shadow = {
      enabled = true,
      range = 20,
      render_power = 3,
      color = "rgba(00000066)",
    },

    blur = {
      enabled = true,
      size = 6,
      passes = 3,
      new_optimizations = true,
    },
  },
})

-- Smoother animations
hl.curve("smoothOut", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })
hl.curve("overshot", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })

hl.animation({ leaf = "windows", enabled = true, speed = 4.5, bezier = "smoothOut" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.5, bezier = "overshot", style = "popin 80%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "smoothOut", style = "popin 80%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4.5, bezier = "smoothOut" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "smoothOut", style = "slide" })

-- Keep windows fully opaque
o.window(".*", { tag = "-default-opacity", opacity = "1 1" })

local function load_if_exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    dofile(path)
  end
end

-- Familiar Desktop title bars (only if that plugin is installed)
load_if_exists(home .. "/.config/omarchy/familiar-titlebars/titlebars.lua")

-- Overrides saved by the Hyprland Tweaks bar widget (loaded last so they win)
load_if_exists(home .. "/.config/hypr/tweaks.lua")
