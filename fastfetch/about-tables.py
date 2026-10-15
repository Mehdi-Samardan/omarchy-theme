#!/usr/bin/env python3
# Draws the whole About page (called from ~/.config/fastfetch/config.jsonc):
# the OMARCHY logo and bordered info tables, stacked and centered. Data comes
# from fastfetch's JSON output plus a few quick commands run in parallel;
# padding is done here so the borders always line up. Icons need a Nerd Font.
import json, os, re, shutil, subprocess, time, unicodedata
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

WIDTH, LEFT = 68, 13   # table width, label column width (icon + label)

MUTED, FG, WHITE = (91, 96, 120), (202, 211, 245), (255, 255, 255)
GREEN, YELLOW, RED = (166, 218, 149), (238, 212, 159), (237, 135, 150)
SECTIONS = {  # title: (color, icon)
    "system":   ((237, 135, 150), ""),
    "hardware": ((138, 173, 244), ""),
    "network":  ((139, 213, 202), ""),
    "desktop":  ((166, 218, 149), ""),
    "dev":      ((198, 160, 246), ""),
}

LOGO = [  # compact two-row OMARCHY
    "█▀█ █▀▄▀█ ▄▀█ █▀█ █▀▀ █ █ █▄█",
    "█▄█ █ ▀ █ █▀█ █▀▄ █▄▄ █▀█  █ ",
]

def c(rgb, bold=False): return "\x1b[0;%s38;2;%d;%d;%dm" % ("1;" if bold else "", *rgb)
RESET = "\x1b[0m"
ANSI = re.compile(r"\x1b\[[0-9;]*m")

def width(s):
    s = ANSI.sub("", s)
    return sum(2 if unicodedata.east_asian_width(ch) in "WF" else 0 if unicodedata.combining(ch) else 1 for ch in s)

def fit(s, n):
    while width(s) > n: s = s[:-2] + "…"
    return s + " " * (n - width(s))

def columns():
    for fd in (2, 0, 1):
        try: return os.get_terminal_size(fd).columns
        except OSError: pass
    try:
        with open("/dev/tty") as tty: return os.get_terminal_size(tty.fileno()).columns
    except OSError: return shutil.get_terminal_size((80, 24)).columns

def sh(cmd):
    try: return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=2).stdout.strip()
    except Exception: return ""

def version(cmd):
    m = re.search(r"\d+(\.\d+)+", sh(cmd + " 2>&1 | head -1"))
    return m.group(0) if m else ""

def fetch():
    mods = ["OS", "Title", "Kernel", "InitSystem", "Bootmgr", "Uptime", "Packages", "Processes", "Loadavg",
            "Host", "Bios", {"type": "CPU", "temp": True}, "CPUUsage",
            {"type": "GPU", "detectionMethod": "pci", "temp": True},
            "Memory", "Swap", {"type": "Disk", "folders": "/"}, "Display", "Sound",
            {"type": "LocalIp", "showSpeed": True, "showMac": True}, "Wifi",
            "WM", "Cursor", "Icons", "Locale", "Media"]
    path = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "about-data.jsonc")
    with open(path, "w") as f: json.dump({"modules": mods}, f)
    out = subprocess.run(["fastfetch", "-c", path, "--format", "json"], capture_output=True, text=True).stdout
    return {m["type"]: m.get("result") for m in json.loads(out or "[]")}

COMMANDS = {
    "aur": "pacman -Qmq | wc -l",
    "omarchy": "omarchy-version",
    "theme": "omarchy-theme-current",
    "font": "omarchy-font-current",
    "editor": "cat ~/.local/state/omarchy/defaults/editor",
    "governor": "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor",
    "vram": "nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits",
    "drives": os.path.join(os.path.dirname(os.path.abspath(__file__)), "drives.sh"),
    "gateway": "ip route show default | awk '{print $3; exit}'",
    "dns": "resolvectl dns 2>/dev/null | grep -oE '([0-9]{1,3}\\.){3}[0-9]{1,3}' | sort -u | head -2 | paste -sd ' '"
           " || awk '/^nameserver/{print $2}' /etc/resolv.conf | head -2 | paste -sd ' '",
    "bluetooth": "timeout 1 bluetoothctl show 2>/dev/null | awk '/Powered:/{print $2; exit}'",
    "keyboard": "hyprctl devices -j | jq -r '[.keyboards[] | select(.main)][0].active_keymap // empty'",
    "windows": "hyprctl clients -j | jq length",
    "workspaces": "hyprctl workspaces -j | jq length",
    "browser": "xdg-settings get default-web-browser",
    "gtk": "gsettings get org.gnome.desktop.interface gtk-theme | tr -d \"'\"",
    "git": "git --version", "python": "python3 --version", "node": "node --version",
    "docker": "docker --version", "mise": "mise --version", "gcc": "gcc --version",
    "rust": "rustc --version", "go": "go version",
}
VERSIONED = {"git", "python", "node", "docker", "mise", "gcc", "rust", "go"}

with ThreadPoolExecutor(max_workers=len(COMMANDS) + 1) as pool:
    data_future = pool.submit(fetch)
    futures = {k: pool.submit(version if k in VERSIONED else sh, cmd) for k, cmd in COMMANDS.items()}
    d = data_future.result()
    x = {k: f.result() for k, f in futures.items()}

def gib(b): return "%.1f GiB" % (b / 1024**3)

def gauge(used, total):
    p = used * 100 // total if total else 0
    rgb = GREEN if p < 60 else YELLOW if p < 85 else RED
    full = round(p / 10)
    return "■" * full + "·" * (10 - full) + f" {p}%", rgb

def temp(t): return f"{t:.0f}°C" if isinstance(t, (int, float)) else None

def ago(seconds):
    m = int(seconds // 60)
    d, h, m = m // 1440, m // 60 % 24, m % 60
    return " ".join(p for p in (f"{d}d" if d else "", f"{h}h" if h else "", f"{m}m") if p)

def synced():
    try: age = int((time.time() - os.stat("/var/lib/pacman/sync/core.db").st_mtime) // 86400)
    except OSError: return None
    return "today" if age == 0 else "1 day ago" if age == 1 else f"{age} days ago"

def join(*parts): return "  ·  ".join(str(p) for p in parts if p)

def terminal():
    # This script runs under fastfetch, so find the real terminal up the process tree.
    known = {"foot", "alacritty", "kitty", "ghostty", "wezterm-gui", "konsole", "xterm"}
    pid = os.getppid()
    while pid > 1:
        try:
            with open(f"/proc/{pid}/comm") as f: name = f.read().strip()
            with open(f"/proc/{pid}/stat") as f: pid = int(f.read().rsplit(")", 1)[1].split()[1])
        except OSError: break
        if name in known: return " ".join(p for p in (name, version(f"{name} --version")) if p)
    return None

def table(title, rows):
    col, icon = SECTIONS[title]; b = c(col)
    inner = WIDTH - LEFT - 7
    head = f"─ {icon}  {title.upper()} "
    lines = [b + "╭" + head + "─" * (LEFT + 2 - width(head)) + "┬" + "─" * (inner + 2) + "╮"]
    for row in rows:
        ic, label, value, *gauge_ = row
        if not value: continue
        if gauge_:
            g, rgb = gauge_[0]
            text = fit(value + "  " + g, inner)
            cell = c(FG) + text[:len(value) + 2] + c(rgb) + text[len(value) + 2:]
        else:
            cell = c(FG) + fit(value, inner)
        lines.append(b + "│ " + c(col) + ic + "  " + c(col, True) + fit(label, LEFT - 3) + b + " │ " + cell + b + " │")
    lines.append(b + "╰" + "─" * (LEFT + 2) + "┴" + "─" * (inner + 2) + "╯")
    return lines

g = lambda k, default=None: d.get(k) if d.get(k) is not None else default
os_, title, k = g("OS", {}), g("Title", {}), g("Kernel", {})
init, boot, pk = g("InitSystem", {}), g("Bootmgr", {}), g("Packages", {})
procs, load = g("Processes", {}), g("Loadavg", [])
host, bios, cpu, usage = g("Host", {}), g("BIOS", {}), g("CPU", {}), g("CPUUsage", [])
gpus = [p for p in g("GPU", []) if p.get("type") != "Integrated"] or g("GPU", [])
mem, swaps, disk = g("Memory", {}), g("Swap", []), (g("Disk", []) or [{}])[0]
disp = (g("Display", []) or [{}])[0]
sound = next((s for s in g("Sound", []) if "main" in s.get("type", [])), {})
nets, wifi = g("LocalIp", []), g("Wifi", [])
wm, cursor, icons, media = g("WM", {}), g("Cursor", {}), g("Icons", {}), g("Media", {})

boot_time = datetime.fromisoformat(d["Uptime"]["bootTime"]) if d.get("Uptime") else None
net = next((n for n in nets if (n.get("defaultRoute") or {}).get("ipv4")), nets[0] if nets else {})
speed = net.get("speed")
speed = (f"{speed / 1000:g} Gbps" if speed >= 1000 else f"{speed} Mbps") if speed else None
w = wifi[0] if wifi else {}
wconn = w.get("conn", {})
wifi_v = join((w.get("inf") or {}).get("description"),
              wconn.get("ssid") if wconn.get("status") == "connected" else wconn.get("status"),
              f"{wconn['signalQuality']:.0f}%" if wconn.get("signalQuality") else None) if w else None
db = disk.get("bytes", {})
swap_used, swap_total = sum(s.get("used", 0) for s in swaps), sum(s.get("total", 0) for s in swaps)
cores = cpu.get("cores", {})
freq = (cpu.get("frequency") or {}).get("max")
cpu_pct = round(sum(usage) / len(usage)) if usage else None
vram = [v.strip() for v in x["vram"].split(",")] if x["vram"].count(",") == 2 else None
shell = os.path.basename(os.environ.get("SHELL", "bash"))
editor = os.path.basename((x["editor"] or os.environ.get("EDITOR", "nvim")).split()[0])
out_ = disp.get("output", {})
song = (media or {}).get("song", {})
playing = join(song.get("name"), song.get("artist")) if song.get("status") == "Playing" else None

system = table("system", [
    ("", "os", join(f"{os_.get('prettyName', '')} {x['omarchy'] or os_.get('versionID', '')}".strip(),
                         f"{os_.get('idLike', '')}-based" if os_.get("idLike") else None)),
    ("", "user", title.get("userName")),
    ("", "host", title.get("hostName")),
    ("", "kernel", join(k.get("release"), k.get("architecture"))),
    ("", "init", f"{init.get('name', '')} {init.get('version', '').split('-')[0]}".strip()),
    ("", "boot", join(boot.get("name"), bios.get("type"),
                           "secure boot " + ("on" if boot.get("secureBoot") else "off") if boot else None)),
    ("", "uptime", join(ago(time.time() - boot_time.timestamp()), "since " + boot_time.strftime("%a %H:%M")) if boot_time else None),
    ("", "packages", join(f"{pk.get('all', 0)} total", f"{pk.get('pacman', 0)} pacman",
                               f"{x['aur']} aur" if x["aur"] not in ("", "0") else None)),
    ("", "synced", synced()),
    ("", "processes", join(f"{procs.get('processes', 0)} running", f"{procs.get('threads', 0)} threads")),
    ("", "load", "  ".join(f"{v:.2f}" for v in load) + "   (1 · 5 · 15 min)" if load else None),
    ("", "locale", g("Locale")),
])
hardware = table("hardware", [
    ("", "board", " ".join(p for p in (host.get("vendor"), host.get("name")) if p)),
    ("", "bios", join(bios.get("version"), bios.get("date"))),
    ("", "cpu", cpu.get("cpu")),
    ("", "cores", join(f"{cores.get('physical', '?')} cores / {cores.get('logical', '?')} threads",
                            f"{freq / 1000:.2f} GHz" if freq else None, cpu.get("march"))),
    ("", "cpu load", f"avg of {len(usage)} threads" if cpu_pct is not None else None,
     gauge(cpu_pct, 100) if cpu_pct is not None else ("", FG)),
    ("", "cpu temp", join(temp(cpu.get("temperature")), f"governor {x['governor']}" if x["governor"] else None)),
    *[("", "gpu", join(p.get("name"), temp(p.get("temperature")))) for p in gpus[:2]],
    ("", "driver", gpus[0].get("driver") if gpus else None),
    ("", "vram", f"{int(vram[0]) / 1024:.1f} / {int(vram[1]) / 1024:.1f} GiB" if vram else None,
     gauge(int(vram[0]), int(vram[1])) if vram else ("", FG)),
    ("", "memory", f"{gib(mem.get('used', 0))} / {gib(mem.get('total', 0))}", gauge(mem.get("used", 0), mem.get("total", 0))),
    ("", "swap", f"{gib(swap_used)} / {gib(swap_total)}" if swap_total else None, gauge(swap_used, swap_total)),
    ("", "disk", f"{gib(db.get('used', 0))} / {gib(db.get('total', 0))}", gauge(db.get("used", 0), db.get("total", 0))),
    ("", "drives", x["drives"].replace(" · ", "  ·  ")),
    ("", "filesystem", join(disk.get("filesystem"), disk.get("mountFrom"))),
    ("", "display", join(f"{out_.get('width', '?')}x{out_.get('height', '?')} @ {round(out_.get('refreshRate') or 0)} Hz",
                              f"{disp['physical'].get('width', 0) and round((disp['physical']['width']**2 + disp['physical']['height']**2) ** .5 / 25.4)}\"" if disp.get("physical") else None,
                              disp.get("name"))),
    ("", "audio", join(sound.get("name"), f"{sound['volume']}%" if sound.get("volume") is not None else None)),
])
network = table("network", [
    ("", "interface", join(net.get("name"), speed)),
    ("", "local ip", (net.get("ipv4") or "").split("/")[0] or None),
    ("", "mac", net.get("mac")),
    ("", "gateway", x["gateway"]),
    ("", "dns", x["dns"]),
    ("", "wifi", wifi_v),
    ("", "bluetooth", {"yes": "on", "no": "off"}.get(x["bluetooth"], x["bluetooth"])),
])
desktop = table("desktop", [
    ("", "wm", join(f"{wm.get('prettyName', '')} {wm.get('version', '')}".strip(), wm.get("protocolName"))),
    ("", "workspaces", join(f"{x['workspaces']} workspaces" if x["workspaces"] else None, f"{x['windows']} windows" if x["windows"] else None)),
    ("", "theme", join(x["theme"], f"gtk {x['gtk']}" if x["gtk"] else None)),
    ("", "terminal", terminal()),
    ("", "shell", " ".join(p for p in (shell, version(f"{shell} --version")) if p)),
    ("", "editor", " ".join(p for p in (editor, version(f"{editor} --version")) if p)),
    ("", "browser", re.sub(r"\.desktop$", "", x["browser"]) or None),
    ("", "font", x["font"]),
    ("", "cursor", join(cursor.get("theme"), cursor.get("size"))),
    ("", "icons", (icons.get("icons2") or icons.get("icons1") or "").split(" [")[0] or None),
    ("", "keyboard", x["keyboard"]),
    ("", "playing", playing),
])
dev = table("dev", [
    ("", "git", x["git"]),
    ("", "python", x["python"]),
    ("", "node", x["node"]),
    ("", "rust", x["rust"]),
    ("", "go", x["go"]),
    ("", "gcc", x["gcc"]),
    ("", "docker", x["docker"]),
    ("", "mise", x["mise"]),
])

cols = columns()
body = []
for t in (system, hardware, network, desktop, dev):
    if len(t) > 2: body += t + [""]

logo = [c(WHITE, True) + row for row in LOGO]
page = [""] + logo + [""] + body
pad = " " * max(0, (cols - WIDTH) // 2)

def center(line):
    return " " * max(0, (cols - width(line)) // 2) + line

print("\n".join(center(l) if l in logo else pad + l for l in page) + RESET)
