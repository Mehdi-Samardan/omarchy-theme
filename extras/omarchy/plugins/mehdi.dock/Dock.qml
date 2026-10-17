import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "mehdi.dock"

  readonly property color accentColor: "#ff0033"
  // Match the visual size of the workspace glyphs (一 二 三 …).
  readonly property real iconSize: Style.font.body + 1

  // Omarchy web apps run as Chrome windows with an appId like
  // "chrome-music.youtube.com__-Default"; map them back to the .desktop
  // entry whose Exec launches that URL so they get their own icon.
  function webAppHost(appId) {
    var m = String(appId || "").match(/^chrome-([^_]+)__/)
    return m ? m[1] : ""
  }

  // Apps whose window appId doesn't match their .desktop file name.
  readonly property var entryAliases: ({
    "GitHub Desktop": "github-desktop"
  })

  function lookupEntry(appId) {
    if (!appId) return null
    if (entryAliases[appId]) return DesktopEntries.byId(entryAliases[appId])
    var host = webAppHost(appId)
    if (host) {
      var apps = DesktopEntries.applications ? DesktopEntries.applications.values : []
      for (var i = 0; i < apps.length; i++) {
        var exec = String(apps[i].execString || "")
        if (exec.indexOf("omarchy-launch-webapp") !== -1 && exec.indexOf("//" + host) !== -1) return apps[i]
      }
      for (var j = 0; j < apps.length; j++) {
        if (String(apps[j].execString || "").indexOf("//www." + host) !== -1) return apps[j]
      }
    }
    return DesktopEntries.byId(appId) || DesktopEntries.heuristicLookup(appId)
  }

  // Apps without a usable themed icon get a bundled one.
  readonly property var iconOverrides: ({
    "org.omarchy.agent": Qt.resolvedUrl("icons/claude.svg"),
    "org.omarchy.about": "file:///usr/share/pixmaps/omarchy.png"
  })

  // Tooltip names for apps without a .desktop entry.
  readonly property var labelOverrides: ({
    "org.omarchy.about": "About"
  })

  function iconFor(entry, appId) {
    if (iconOverrides[appId]) return iconOverrides[appId]
    var name = entry && entry.icon ? entry.icon : appId
    if (!name) return Quickshell.iconPath("application-x-executable")
    if (name.charAt(0) === "/") return "file://" + name
    return Quickshell.iconPath(name, "application-x-executable")
  }

  // One entry per app, in the order the windows were opened.
  readonly property var apps: {
    var list = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    var byKey = {}
    var out = []
    for (var i = 0; i < list.length; i++) {
      var t = list[i]
      if (!t || !t.appId) continue
      var entry = lookupEntry(t.appId)
      var key = (entry ? entry.id : t.appId).toLowerCase()
      if (!byKey[key]) {
        byKey[key] = { key: key, appId: t.appId, entry: entry, windows: [] }
        out.push(byKey[key])
      }
      byKey[key].windows.push(t)
    }
    return out
  }

  function isActive(app) {
    for (var i = 0; i < app.windows.length; i++) if (app.windows[i].activated) return true
    return false
  }

  // Focus the app; when it is already focused, cycle through its windows.
  function focusApp(app) {
    var w = app.windows
    var current = -1
    for (var i = 0; i < w.length; i++) if (w[i].activated) { current = i; break }
    w[(current + 1) % w.length].activate()
  }

  visible: apps.length > 0
  implicitWidth: visible ? row.implicitWidth + Style.space(4) : 0
  implicitHeight: barSize

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(2)


    Repeater {
      model: root.apps

      Item {
        id: slot
        required property var modelData
        readonly property bool active: root.isActive(modelData)
        readonly property string label: root.labelOverrides[modelData.appId] || (modelData.entry ? modelData.entry.name : modelData.appId)

        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(20)
        height: root.barSize

        Image {
          anchors.centerIn: parent
          width: root.iconSize
          height: root.iconSize
          sourceSize.width: root.iconSize * 2
          sourceSize.height: root.iconSize * 2
          fillMode: Image.PreserveAspectFit
          smooth: true
          asynchronous: true
          source: root.iconFor(slot.modelData.entry, slot.modelData.appId)
          opacity: slot.active || mouse.containsMouse ? 1.0 : 0.6
          scale: mouse.pressed ? 0.88 : 1.0
          Behavior on opacity { NumberAnimation { duration: 120 } }
          Behavior on scale { NumberAnimation { duration: 80 } }
        }

        // Window count when an app has more than one window open.
        Text {
          visible: slot.modelData.windows.length > 1
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(3)
          text: slot.modelData.windows.length
          color: root.accentColor
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption - 2
          font.bold: true
        }

        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.MiddleButton
          onClicked: function(m) {
            if (m.button === Qt.MiddleButton) {
              var w = slot.modelData.windows
              for (var i = 0; i < w.length; i++) if (w[i].activated) { w[i].close(); return }
              w[w.length - 1].close()
            } else {
              root.focusApp(slot.modelData)
            }
          }
          onEntered: if (root.bar) root.bar.showTooltip(slot, slot.label)
          onExited: if (root.bar) root.bar.hideTooltip(slot)
        }
      }
    }

  }
}
