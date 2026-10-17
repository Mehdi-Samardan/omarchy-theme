import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Panel {
  id: root
  moduleName: "mehdi.hyprtweaks"
  ipcTarget: "mehdi.hyprtweaks"

  // Only options the user actually changed are stored (as JSON) and rendered
  // into a Lua file that looknfeel.lua loads last, so they win over the
  // defaults and survive reloads/reboots.
  readonly property string stateFile: Quickshell.env("HOME") + "/.local/state/omarchy/mehdi-hyprtweaks.json"
  readonly property string tweaksFile: Quickshell.env("HOME") + "/.config/hypr/tweaks.lua"

  // ---------- Option catalogue ----------
  // type: bool | int | float | enum | color | anim
  // opt:  Hyprland option name as `hyprctl getoption` expects it.
  //       anim options use "anim:<leaf>:<speed|style>".
  readonly property var sections: [
    { title: "General", icon: "", items: [
      { opt: "general:border_size", label: "Border size", type: "int", min: 0, max: 10, unit: "px" },
      { opt: "general:gaps_in", label: "Gaps between windows", type: "int", min: 0, max: 40, unit: "px" },
      { opt: "general:gaps_out", label: "Gaps to screen edge", type: "int", min: 0, max: 60, unit: "px" },
      { opt: "general:gaps_workspaces", label: "Gaps between workspaces", type: "int", min: 0, max: 100, unit: "px" },
      { opt: "general:layout", label: "Layout", type: "enum", options: ["dwindle", "master", "scrolling"] },
      { opt: "general:resize_on_border", label: "Resize by dragging border", type: "bool" },
      { opt: "general:extend_border_grab_area", label: "Border grab area", type: "int", min: 0, max: 50, unit: "px", dependsOn: "general:resize_on_border" },
      { opt: "general:hover_icon_on_border", label: "Resize cursor on border", type: "bool" },
      { opt: "general:snap:enabled", label: "Snap floating windows", type: "bool" },
      { opt: "general:allow_tearing", label: "Allow tearing", type: "bool" },
      { opt: "general:no_focus_fallback", label: "No focus fallback", type: "bool" }
    ]},
    { title: "Colors", icon: "󰏘", items: [
      { opt: "general:col.active_border", label: "Active border", type: "color" },
      { opt: "general:col.inactive_border", label: "Inactive border", type: "color" },
      { opt: "decoration:shadow:color", label: "Shadow", type: "color" }
    ]},
    { title: "Decoration", icon: "", items: [
      { opt: "decoration:rounding", label: "Corner rounding", type: "int", min: 0, max: 30, unit: "px" },
      { opt: "decoration:rounding_power", label: "Rounding curve", type: "float", min: 1, max: 10, step: 0.1 },
      { opt: "decoration:active_opacity", label: "Active opacity", type: "float", min: 0.1, max: 1, step: 0.01 },
      { opt: "decoration:inactive_opacity", label: "Inactive opacity", type: "float", min: 0.1, max: 1, step: 0.01 },
      { opt: "decoration:fullscreen_opacity", label: "Fullscreen opacity", type: "float", min: 0.1, max: 1, step: 0.01 },
      { opt: "decoration:dim_inactive", label: "Dim inactive windows", type: "bool" },
      { opt: "decoration:dim_strength", label: "Dim strength", type: "float", min: 0, max: 1, step: 0.01, dependsOn: "decoration:dim_inactive" },
      { opt: "decoration:dim_special", label: "Dim behind special workspace", type: "float", min: 0, max: 1, step: 0.01 },
      { opt: "decoration:dim_around", label: "Dim around (dimaround rule)", type: "float", min: 0, max: 1, step: 0.01 },
      { opt: "decoration:border_part_of_window", label: "Border is part of window", type: "bool" }
    ]},
    { title: "Blur", icon: "", items: [
      { opt: "decoration:blur:enabled", label: "Enable blur", type: "bool" },
      { opt: "decoration:blur:size", label: "Size", type: "int", min: 1, max: 20, dependsOn: "decoration:blur:enabled" },
      { opt: "decoration:blur:passes", label: "Passes", type: "int", min: 1, max: 6, dependsOn: "decoration:blur:enabled" },
      { opt: "decoration:blur:noise", label: "Noise", type: "float", min: 0, max: 0.2, step: 0.005, dependsOn: "decoration:blur:enabled" },
      { opt: "decoration:blur:contrast", label: "Contrast", type: "float", min: 0, max: 2, step: 0.01, dependsOn: "decoration:blur:enabled" },
      { opt: "decoration:blur:brightness", label: "Brightness", type: "float", min: 0, max: 2, step: 0.01, dependsOn: "decoration:blur:enabled" },
      { opt: "decoration:blur:vibrancy", label: "Vibrancy", type: "float", min: 0, max: 1, step: 0.01, dependsOn: "decoration:blur:enabled" },
      { opt: "decoration:blur:vibrancy_darkness", label: "Vibrancy darkness", type: "float", min: 0, max: 1, step: 0.01, dependsOn: "decoration:blur:enabled" },
      { opt: "decoration:blur:xray", label: "X-ray (see wallpaper)", type: "bool", dependsOn: "decoration:blur:enabled" },
      { opt: "decoration:blur:ignore_opacity", label: "Ignore window opacity", type: "bool", dependsOn: "decoration:blur:enabled" },
      { opt: "decoration:blur:special", label: "Blur special workspace", type: "bool", dependsOn: "decoration:blur:enabled" },
      { opt: "decoration:blur:popups", label: "Blur popups", type: "bool", dependsOn: "decoration:blur:enabled" },
      { opt: "decoration:blur:new_optimizations", label: "Optimizations", type: "bool", dependsOn: "decoration:blur:enabled" }
    ]},
    { title: "Shadow", icon: "", items: [
      { opt: "decoration:shadow:enabled", label: "Enable shadow", type: "bool" },
      { opt: "decoration:shadow:range", label: "Range", type: "int", min: 0, max: 100, unit: "px", dependsOn: "decoration:shadow:enabled" },
      { opt: "decoration:shadow:render_power", label: "Falloff power", type: "int", min: 1, max: 4, dependsOn: "decoration:shadow:enabled" },
      { opt: "decoration:shadow:scale", label: "Scale", type: "float", min: 0, max: 1, step: 0.01, dependsOn: "decoration:shadow:enabled" },
      { opt: "decoration:shadow:sharp", label: "Sharp shadow", type: "bool", dependsOn: "decoration:shadow:enabled" }
    ]},
    { title: "Animations", icon: "", items: [
      { opt: "animations:enabled", label: "Enable animations", type: "bool" },
      { opt: "anim:windowsIn:style", label: "Window open style", type: "enum", options: ["popin 80%", "slide", "gnomed"], dependsOn: "animations:enabled" },
      { opt: "anim:windows:speed", label: "Window speed (lower = faster)", type: "float", min: 0.5, max: 10, step: 0.1, dependsOn: "animations:enabled" },
      { opt: "anim:workspaces:style", label: "Workspace style", type: "enum", options: ["slide", "slidevert", "slidefade", "fade"], dependsOn: "animations:enabled" },
      { opt: "anim:workspaces:speed", label: "Workspace speed (lower = faster)", type: "float", min: 0.5, max: 10, step: 0.1, dependsOn: "animations:enabled" },
      { opt: "anim:fade:speed", label: "Fade speed (lower = faster)", type: "float", min: 0.5, max: 10, step: 0.1, dependsOn: "animations:enabled" },
      { opt: "anim:border:speed", label: "Border speed (lower = faster)", type: "float", min: 0.5, max: 10, step: 0.1, dependsOn: "animations:enabled" },
      { opt: "animations:workspace_wraparound", label: "Workspace wraparound", type: "bool", dependsOn: "animations:enabled" },
      { opt: "misc:animate_manual_resizes", label: "Animate manual resizes", type: "bool", dependsOn: "animations:enabled" },
      { opt: "misc:animate_mouse_windowdragging", label: "Animate mouse dragging", type: "bool", dependsOn: "animations:enabled" }
    ]},
    { title: "Input", icon: "", items: [
      { opt: "input:sensitivity", label: "Mouse sensitivity", type: "float", min: -1, max: 1, step: 0.05 },
      { opt: "input:accel_profile", label: "Acceleration", type: "enum", options: [{ value: "", label: "default" }, "adaptive", "flat"] },
      { opt: "input:follow_mouse", label: "Focus follows mouse", type: "enum", valueType: "int", options: [{ value: "0", label: "off" }, { value: "1", label: "always" }, { value: "2", label: "loose" }, { value: "3", label: "click" }] },
      { opt: "input:scroll_factor", label: "Mouse scroll speed", type: "float", min: 0.1, max: 3, step: 0.05 },
      { opt: "input:natural_scroll", label: "Natural scroll (mouse)", type: "bool" },
      { opt: "input:left_handed", label: "Left handed", type: "bool" },
      { opt: "input:repeat_rate", label: "Key repeat rate", type: "int", min: 10, max: 100, unit: "/s" },
      { opt: "input:repeat_delay", label: "Key repeat delay", type: "int", min: 100, max: 1000, unit: "ms" },
      { opt: "input:touchpad:natural_scroll", label: "Natural scroll (touchpad)", type: "bool" },
      { opt: "input:touchpad:scroll_factor", label: "Touchpad scroll speed", type: "float", min: 0.1, max: 3, step: 0.05 },
      { opt: "input:touchpad:tap-to-click", label: "Tap to click", type: "bool" },
      { opt: "input:touchpad:disable_while_typing", label: "Disable touchpad while typing", type: "bool" }
    ]},
    { title: "Cursor", icon: "", items: [
      { opt: "cursor:zoom_factor", label: "Screen zoom", type: "float", min: 1, max: 5, step: 0.05 },
      { opt: "cursor:inactive_timeout", label: "Hide after idle (0 = never)", type: "float", min: 0, max: 30, step: 0.5, unit: "s" },
      { opt: "cursor:hide_on_key_press", label: "Hide while typing", type: "bool" },
      { opt: "cursor:no_warps", label: "Never warp cursor", type: "bool" },
      { opt: "cursor:no_hardware_cursors", label: "Hardware cursor", type: "enum", valueType: "int", options: [{ value: "0", label: "on" }, { value: "1", label: "off" }, { value: "2", label: "auto" }] }
    ]},
    { title: "Layouts", icon: "", items: [
      { opt: "dwindle:preserve_split", label: "Dwindle: preserve split", type: "bool" },
      { opt: "dwindle:smart_split", label: "Dwindle: smart split", type: "bool" },
      { opt: "dwindle:smart_resizing", label: "Dwindle: smart resizing", type: "bool" },
      { opt: "dwindle:force_split", label: "Dwindle: new window side", type: "enum", valueType: "int", options: [{ value: "0", label: "mouse" }, { value: "1", label: "left/top" }, { value: "2", label: "right/bottom" }] },
      { opt: "dwindle:default_split_ratio", label: "Dwindle: split ratio", type: "float", min: 0.1, max: 1.9, step: 0.05 },
      { opt: "dwindle:split_width_multiplier", label: "Dwindle: split width multiplier", type: "float", min: 0.5, max: 2, step: 0.05 },
      { opt: "master:mfact", label: "Master: size", type: "float", min: 0.1, max: 0.9, step: 0.01 },
      { opt: "master:new_status", label: "Master: new window", type: "enum", options: ["master", "slave", "inherit"] },
      { opt: "master:orientation", label: "Master: position", type: "enum", options: ["left", "right", "top", "bottom", "center"] },
      { opt: "master:new_on_top", label: "Master: new on top", type: "bool" },
      { opt: "scrolling:column_width", label: "Scrolling: column width", type: "float", min: 0.1, max: 1, step: 0.01 }
    ]},
    { title: "Groups", icon: "", items: [
      { opt: "group:groupbar:enabled", label: "Show group bar", type: "bool" },
      { opt: "group:groupbar:font_size", label: "Group bar font size", type: "int", min: 6, max: 24, unit: "px", dependsOn: "group:groupbar:enabled" },
      { opt: "group:groupbar:height", label: "Group bar height", type: "int", min: 10, max: 40, unit: "px", dependsOn: "group:groupbar:enabled" },
      { opt: "group:auto_group", label: "Auto group new windows", type: "bool" }
    ]},
    { title: "Misc & Performance", icon: "", items: [
      { opt: "misc:vrr", label: "Variable refresh rate", type: "enum", valueType: "int", options: [{ value: "0", label: "off" }, { value: "1", label: "on" }, { value: "2", label: "fullscreen" }, { value: "3", label: "games" }] },
      { opt: "render:direct_scanout", label: "Direct scanout", type: "enum", valueType: "int", options: [{ value: "0", label: "off" }, { value: "1", label: "on" }, { value: "2", label: "games" }] },
      { opt: "render:new_render_scheduling", label: "New render scheduling", type: "bool" },
      { opt: "misc:focus_on_activate", label: "Focus apps that request it", type: "bool" },
      { opt: "misc:enable_swallow", label: "Terminal swallowing", type: "bool" },
      { opt: "misc:close_special_on_empty", label: "Close empty special workspace", type: "bool" },
      { opt: "misc:middle_click_paste", label: "Middle click paste", type: "bool" },
      { opt: "misc:mouse_move_enables_dpms", label: "Mouse wakes screen", type: "bool" },
      { opt: "misc:key_press_enables_dpms", label: "Key press wakes screen", type: "bool" },
      { opt: "binds:workspace_back_and_forth", label: "Workspace back and forth", type: "bool" },
      { opt: "binds:allow_workspace_cycles", label: "Allow workspace cycles", type: "bool" },
      { opt: "xwayland:force_zero_scaling", label: "XWayland zero scaling", type: "bool" }
    ]}
  ]

  property var values: ({})       // opt -> current value
  property var overrides: ({})    // opt -> value the user set
  property var animState: ({})    // leaf -> { speed, bezier, style, enabled }
  property string search: ""
  property var expanded: ({ "General": true })
  readonly property int overrideCount: Object.keys(overrides).length

  function allItems() {
    var out = []
    for (var i = 0; i < sections.length; i++) out = out.concat(sections[i].items)
    return out
  }
  function filteredItems(section) {
    var q = search.trim().toLowerCase()
    if (q === "") return section.items
    return section.items.filter(function(it) {
      return it.label.toLowerCase().indexOf(q) >= 0 || it.opt.toLowerCase().indexOf(q) >= 0
    })
  }
  function isExpanded(title) { return search.trim() !== "" || !!expanded[title] }
  function toggleSection(title) {
    var copy = Object.assign({}, expanded)
    copy[title] = !copy[title]
    expanded = copy
  }
  function itemActive(it) { return !it.dependsOn || !!values[it.dependsOn] }

  // ---------- Lua rendering ----------
  function luaValue(it, v) {
    if (it.type === "color") return "\"rgba(" + v + ")\""
    if (it.type === "enum" && it.valueType !== "int") return JSON.stringify(String(v))
    return String(v)
  }
  function luaPath(opt) { return opt.replace(/-/g, "_").split(/[:.]/) }
  function luaTable(tree, indent) {
    var pad = "  ".repeat(indent)
    var out = "{\n"
    for (var k in tree) {
      var v = tree[k]
      out += pad + "  " + k + " = " + (typeof v === "object" ? luaTable(v, indent + 1) : v) + ",\n"
    }
    return out + pad + "}"
  }
  function itemFor(opt) {
    var items = allItems()
    for (var i = 0; i < items.length; i++) if (items[i].opt === opt) return items[i]
    return null
  }
  // Lua for a set of { opt: value } — one hl.config() plus one hl.animation() per leaf.
  function luaFor(map) {
    var tree = {}, leaves = {}, hasConfig = false
    for (var opt in map) {
      var it = itemFor(opt)
      if (!it) continue
      if (it.type === "anim" || opt.indexOf("anim:") === 0) {
        var p = opt.split(":")
        if (!leaves[p[1]]) leaves[p[1]] = {}
        leaves[p[1]][p[2]] = map[opt]
        continue
      }
      var parts = luaPath(opt)
      var node = tree
      for (var i = 0; i < parts.length - 1; i++) {
        if (!node[parts[i]]) node[parts[i]] = {}
        node = node[parts[i]]
      }
      node[parts[parts.length - 1]] = luaValue(it, map[opt])
      hasConfig = true
    }
    var out = hasConfig ? "hl.config(" + luaTable(tree, 0) + ")\n" : ""
    for (var leaf in leaves) {
      var s = Object.assign({ speed: 5, bezier: "default", style: "" }, animState[leaf] || {}, leaves[leaf])
      out += "hl.animation({ leaf = " + JSON.stringify(leaf) + ", enabled = true, speed = " + Number(s.speed) +
             ", bezier = " + JSON.stringify(s.bezier) + (s.style ? ", style = " + JSON.stringify(s.style) : "") + " })\n"
    }
    return out
  }

  // ---------- Changing values ----------
  function setValue(opt, v, persist) {
    var vc = Object.assign({}, values); vc[opt] = v; values = vc
    var oc = Object.assign({}, overrides); oc[opt] = v; overrides = oc
    var one = {}; one[opt] = v
    liveApply(luaFor(one))
    if (opt.indexOf("anim:") === 0) {
      var p = opt.split(":")
      var ac = Object.assign({}, animState)
      ac[p[1]] = Object.assign({}, ac[p[1]] || {}); ac[p[1]][p[2]] = v
      animState = ac
    }
    if (persist) save(false)
  }
  function resetOne(opt) {
    var oc = Object.assign({}, overrides); delete oc[opt]; overrides = oc
    save(true)
  }
  function resetAll() {
    overrides = {}
    save(true)
  }

  property string pendingEval: ""
  function liveApply(code) {
    pendingEval = code
    if (!evalProc.running) runEval()
  }
  function runEval() {
    if (pendingEval === "") return
    evalProc.command = ["hyprctl", "eval", pendingEval]
    pendingEval = ""
    evalProc.running = true
  }
  Process {
    id: evalProc
    onExited: root.runEval()
  }

  property bool reloadAfterSave: false
  function save(reload) {
    reloadAfterSave = reloadAfterSave || reload
    saveTimer.restart()
  }
  Timer {
    id: saveTimer
    interval: 300
    onTriggered: {
      var lua = "-- Generated by the mehdi.hyprtweaks bar widget. Edits here are overwritten.\n" + root.luaFor(root.overrides)
      var reload = root.reloadAfterSave
      root.reloadAfterSave = false
      saveProc.command = ["bash", "-c",
        "mkdir -p \"$(dirname \"$3\")\"; printf '%s' \"$1\" > \"$2\"; printf '%s\\n' \"$4\" > \"$3\"; " +
        "if [ \"$5\" = 1 ]; then hyprctl reload >/dev/null; fi",
        "_", lua, root.tweaksFile, root.stateFile, JSON.stringify(root.overrides), reload ? "1" : "0"]
      saveProc.running = true
    }
  }
  Process {
    id: saveProc
    onExited: if (String(command[command.length - 1]) === "1") root.refresh()
  }

  // ---------- Load current values from Hyprland ----------
  function refresh() {
    var opts = allItems().filter(function(it) { return it.opt.indexOf("anim:") !== 0 }).map(function(it) { return it.opt })
    loadProc.optList = opts
    loadProc.command = ["bash", "-c",
      "for o in \"${@:2}\"; do hyprctl getoption \"$o\" -j | tr -d '\\n'; echo; done; " +
      "hyprctl animations -j | tr -d '\\n'; echo; cat \"$1\" 2>/dev/null | tr -d '\\n'; echo",
      "_", root.stateFile].concat(opts)
    loadProc.running = true
  }
  function hexFromGradient(g) {
    var argb = String(g).split(" ")[0]
    if (argb.length !== 8) return "000000ff"
    return argb.substr(2) + argb.substr(0, 2)
  }
  Process {
    id: loadProc
    property var optList: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text).split("\n")
        var opts = loadProc.optList
        var v = {}
        for (var i = 0; i < opts.length; i++) {
          try {
            var o = JSON.parse(lines[i])
            var it = root.itemFor(opts[i])
            if (o.bool !== undefined) v[opts[i]] = !!o.bool
            else if (o.int !== undefined) v[opts[i]] = it && it.type === "enum" ? String(o.int) : o.int
            else if (o.float !== undefined) v[opts[i]] = Math.round(o.float * 1000) / 1000
            else if (o.css !== undefined) v[opts[i]] = Math.max.apply(null, String(o.css).split(" ").map(Number))
            else if (o.gradient !== undefined) v[opts[i]] = root.hexFromGradient(o.gradient)
            else if (o.str !== undefined) v[opts[i]] = o.str === "[[EMPTY]]" ? "" : o.str
          } catch (e) {}
        }
        try {
          var anims = JSON.parse(lines[opts.length])[0]
          var anim = {}
          for (var j = 0; j < anims.length; j++) {
            var a = anims[j]
            anim[a.name] = { speed: a.speed, bezier: a.bezier, style: a.style, enabled: a.enabled }
            v["anim:" + a.name + ":speed"] = a.speed
            v["anim:" + a.name + ":style"] = a.style
          }
          root.animState = anim
        } catch (e) {}
        try { root.overrides = JSON.parse(lines[opts.length + 1]) || {} } catch (e) { root.overrides = {} }
        root.values = v
      }
    }
  }

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) refresh()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    tooltipText: "Hyprland settings"
    onPressed: function(b) { root.toggle() }
  }

  function decimalsFor(step) {
    if (!step || step >= 1) return 0
    if (step >= 0.1) return 1
    if (step >= 0.01) return 2
    return 3
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(header.implicitHeight + Style.space(12) + listColumn.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        // ---------- Hero ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            text: ""
            color: Color.accent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: resetAllText.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Hyprland"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              text: root.overrideCount === 0 ? "NO CHANGES" : (root.overrideCount + (root.overrideCount === 1 ? " CHANGE" : " CHANGES"))
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
          }

          Text {
            id: resetAllText
            text: "Reset all"
            visible: root.overrideCount > 0
            color: resetAllMouse.containsMouse ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            MouseArea {
              id: resetAllMouse
              anchors.fill: parent
              anchors.margins: -Style.space(6)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.resetAll()
            }
          }
        }

        TextField {
          width: parent.width
          placeholderText: "Search settings…"
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          foreground: root.bar.foreground
          onTextChanged: root.search = text
        }
      }

      Flickable {
        id: flick
        anchors.top: header.bottom
        anchors.topMargin: Style.space(12)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: listColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: listColumn
          width: flick.width - Style.space(10)
          spacing: Style.space(4)

          Repeater {
            model: root.sections

            Column {
              id: sectionCol
              required property var modelData
              readonly property var shown: root.filteredItems(modelData)
              readonly property bool open: root.isExpanded(modelData.title)
              width: listColumn.width
              spacing: Style.space(10)
              visible: shown.length > 0

              // Section header (click to collapse/expand)
              Item {
                width: parent.width
                implicitHeight: Style.space(30)

                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: sectionMouse.containsMouse ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"
                }
                Text {
                  id: sectionIcon
                  text: sectionCol.modelData.icon
                  color: Color.accent
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                  width: Style.space(22)
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  text: sectionCol.modelData.title
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                  anchors.left: sectionIcon.right
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  text: sectionCol.open ? "" : ""
                  color: Qt.darker(root.bar.foreground, 1.4)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                }
                MouseArea {
                  id: sectionMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleSection(sectionCol.modelData.title)
                }
              }

              Column {
                width: parent.width - Style.space(12)
                x: Style.space(6)
                spacing: Style.space(12)
                visible: sectionCol.open
                bottomPadding: Style.space(8)

                Repeater {
                  model: sectionCol.open ? sectionCol.shown : []

                  Item {
                    id: row
                    required property var modelData
                    readonly property var it: modelData
                    readonly property var val: root.values[it.opt]
                    readonly property bool modified: root.overrides[it.opt] !== undefined
                    readonly property bool isSlider: it.type === "int" || it.type === "float"
                    width: parent.width
                    implicitHeight: isSlider ? sliderBox.implicitHeight
                                  : it.type === "enum" ? enumBox.implicitHeight
                                  : it.type === "color" ? colorBox.implicitHeight
                                  : boolBox.implicitHeight
                    opacity: root.itemActive(it) ? 1 : 0.35
                    enabled: root.itemActive(it)

                    // Label + modified marker + value, shared by all rows
                    Item {
                      id: labelRow
                      width: parent.width
                      implicitHeight: label.implicitHeight
                      anchors.top: parent.top
                      anchors.topMargin: row.it.type === "bool" ? (boolBox.implicitHeight - implicitHeight) / 2 : 0

                      Text {
                        id: label
                        text: row.it.label
                        color: row.modified ? Color.accent : root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.body
                        anchors.left: parent.left
                        anchors.right: resetOneText.left
                        anchors.rightMargin: Style.space(6)
                        elide: Text.ElideRight
                      }
                      Text {
                        id: resetOneText
                        text: ""
                        visible: row.modified
                        color: resetOneMouse.containsMouse ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.4)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        anchors.right: valueText.left
                        anchors.rightMargin: Style.space(8)
                        anchors.verticalCenter: label.verticalCenter
                        MouseArea {
                          id: resetOneMouse
                          anchors.fill: parent
                          anchors.margins: -Style.space(4)
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.resetOne(row.it.opt)
                        }
                      }
                      Text {
                        id: valueText
                        visible: row.isSlider
                        width: visible ? implicitWidth
                             : row.it.type === "bool" ? toggle.width
                             : row.it.type === "color" ? Style.space(140) : 0
                        text: row.isSlider ? Number(slider.liveValue).toFixed(root.decimalsFor(row.it.type === "int" ? 1 : row.it.step)) + (row.it.unit || "") : ""
                        color: Qt.darker(root.bar.foreground, 1.4)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(4)
                        anchors.verticalCenter: label.verticalCenter
                      }
                    }

                    // bool
                    Item {
                      id: boolBox
                      visible: row.it.type === "bool"
                      width: parent.width
                      implicitHeight: toggle.implicitHeight
                      ToggleSwitch {
                        id: toggle
                        anchors.right: parent.right
                        checked: !!row.val
                        onToggled: root.setValue(row.it.opt, !row.val, true)
                      }
                    }

                    // int / float
                    Column {
                      id: sliderBox
                      visible: row.isSlider
                      width: parent.width
                      spacing: Style.space(2)
                      Item { width: 1; height: labelRow.implicitHeight }
                      PanelSlider {
                        id: slider
                        bar: root.bar
                        width: parent.width
                        minimum: row.it.min !== undefined ? row.it.min : 0
                        maximum: row.it.max !== undefined ? row.it.max : 1
                        step: row.it.type === "int" ? 1 : (row.it.step || 0.01)
                        integer: row.it.type === "int"
                        value: typeof row.val === "number" ? row.val : minimum
                        onMoved: function(v) { root.setValue(row.it.opt, row.clean(v), false) }
                        onReleased: function(v) { root.setValue(row.it.opt, row.clean(v), true) }
                        onRightClicked: if (row.modified) root.resetOne(row.it.opt)
                      }
                    }
                    function clean(v) {
                      if (it.type === "int") return Math.round(v)
                      var s = it.step || 0.01
                      return Number((Math.round(v / s) * s).toFixed(root.decimalsFor(s)))
                    }

                    // enum
                    Column {
                      id: enumBox
                      visible: row.it.type === "enum"
                      width: parent.width
                      spacing: Style.space(6)
                      Item { width: 1; height: labelRow.implicitHeight }
                      Flow {
                        width: parent.width
                        ButtonGroup {
                          options: row.it.type === "enum" ? row.it.options : []
                          value: row.val !== undefined ? String(row.val) : ""
                          foreground: root.bar.foreground
                          background: root.bar.background
                          accent: Color.accent
                          fontFamily: root.bar.fontFamily
                          fontSize: Style.font.caption
                          focusable: false
                          onChanged: function(v) { root.setValue(row.it.opt, v, true) }
                        }
                      }
                    }

                    // color (RRGGBBAA)
                    Item {
                      id: colorBox
                      visible: row.it.type === "color"
                      width: parent.width
                      implicitHeight: hexField.implicitHeight
                      Rectangle {
                        id: swatch
                        width: Style.space(22)
                        height: width
                        radius: Style.cornerRadius
                        anchors.right: hexField.left
                        anchors.rightMargin: Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        border.width: 1
                        border.color: Qt.darker(root.bar.foreground, 1.8)
                        color: {
                          var h = String(row.val || "000000ff")
                          return "#" + h.substr(6, 2) + h.substr(0, 6)
                        }
                      }
                      TextField {
                        id: hexField
                        width: Style.space(110)
                        anchors.right: parent.right
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        foreground: root.bar.foreground
                        text: String(row.val || "")
                        placeholderText: "RRGGBBAA"
                        validator: RegularExpressionValidator { regularExpression: /[0-9a-fA-F]{0,8}/ }
                        onEditingFinished: {
                          var t = text.toLowerCase()
                          if (t.length === 6) t += "ff"
                          if (t.length === 8) root.setValue(row.it.opt, t, true)
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
