import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Paste a link, pick a resolution (or audio-only mp3) and download it with
// yt-dlp through downloader.py. Downloads keep running when the panel is
// closed; the bar icon shows the progress and a notification fires at the end.
Panel {
  id: root
  moduleName: "mehdi.downloader"
  ipcTarget: "mehdi.downloader"

  readonly property string helper: decodeURIComponent(String(Qt.resolvedUrl("downloader.py")).replace(/^file:\/\//, ""))
  readonly property string outDir: (Quickshell.env("XDG_VIDEOS_DIR") || Quickshell.env("HOME") + "/Videos") + "/Downloads"

  // idle | loading | ready | error | downloading | done
  property string status: "idle"
  property string errorText: ""
  property string url: ""
  property var info: null
  property var options: []        // [{ quality, label, detail }]
  property int selectedIndex: 0
  property string activeQuality: ""
  property string activeLabel: ""
  property real percent: 0
  property string speed: ""
  property string eta: ""
  property string stage: ""
  property string doneFile: ""

  readonly property bool busy: status === "loading" || status === "downloading"

  function humanSize(bytes) {
    if (!bytes) return ""
    if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " GB"
    return Math.max(1, Math.round(bytes / 1048576)) + " MB"
  }

  function humanTime(sec) {
    sec = Math.round(sec || 0)
    var h = Math.floor(sec / 3600), m = Math.floor(sec / 60) % 60, s = sec % 60
    var mm = h > 0 && m < 10 ? "0" + m : String(m)
    return (h > 0 ? h + ":" : "") + mm + ":" + (s < 10 ? "0" : "") + s
  }

  function heightLabel(h) {
    if (h >= 4320) return "8K"
    if (h >= 2160) return "4K"
    if (h >= 1440) return "2K"
    if (h >= 1080) return "Full HD"
    if (h >= 720) return "HD"
    return ""
  }

  function fetchInfo() {
    var u = urlField.text.trim()
    if (!/^https?:\/\//i.test(u)) { status = "error"; errorText = "Paste a link that starts with http:// or https://"; return }
    if (infoProc.running) infoProc.running = false
    url = u
    info = null
    options = []
    status = "loading"
    infoProc.command = ["python3", helper, "info", u]
    infoProc.running = true
  }

  function applyInfo(raw) {
    var d = null
    try { d = JSON.parse(raw) } catch (e) { d = { error: "Could not read yt-dlp output" } }
    if (!d || d.error) { status = "error"; errorText = d ? d.error : "Unknown error"; return }
    var opts = []
    for (var i = 0; i < d.heights.length; i++) {
      var h = d.heights[i]
      opts.push({ quality: String(h.height), label: h.height + "p",
                  tag: heightLabel(h.height), detail: humanSize(h.size) })
    }
    opts.push({ quality: "audio", label: "Audio only", tag: "MP3", detail: humanSize(d.audioSize) })
    info = d
    options = opts
    selectedIndex = 0
    status = "ready"
    keyCatcher.forceActiveFocus()
  }

  function startDownload(i) {
    if (i < 0 || i >= options.length || dlProc.running) return
    var o = options[i]
    activeQuality = o.quality
    activeLabel = o.quality === "audio" ? "MP3" : o.label
    percent = 0; speed = ""; eta = ""; stage = ""; doneFile = ""; errorText = ""
    status = "downloading"
    dlProc.command = ["python3", helper, "download", url, o.quality, outDir]
    dlProc.running = true
  }

  function cancelDownload() {
    dlProc.running = false
    status = "ready"
  }

  function handleLine(line) {
    var parts = String(line).trim().split(" ")
    var kind = parts.shift()
    if (kind === "progress") {
      var p = parseFloat(parts[0])
      if (!isNaN(p)) percent = p
      speed = parts[1] && parts[1] !== "N/A" && parts[1] !== "Unknown" ? parts[1] : ""
      eta = parts[2] && parts[2] !== "N/A" && parts[2] !== "Unknown" ? parts[2] : ""
      stage = ""
    } else if (kind === "stage") {
      stage = parts.join(" ")
    } else if (kind === "done") {
      doneFile = parts.join(" ")
      percent = 100
      status = "done"
      var name = doneFile.split("/").pop()
      Quickshell.execDetached(["notify-send", "-a", "Video Downloader", "-i", "folder-download", "Download finished", name])
    } else if (kind === "error") {
      status = "error"
      errorText = parts.join(" ")
      Quickshell.execDetached(["notify-send", "-a", "Video Downloader", "-u", "critical", "Download failed", errorText])
    }
  }

  function reset() {
    if (dlProc.running) return
    status = "idle"; info = null; options = []; errorText = ""; urlField.text = ""
    urlField.forceActiveFocus()
  }

  Process {
    id: infoProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (root.status === "loading") root.applyInfo(text)
    }
  }

  Process {
    id: dlProc
    running: false
    stdout: SplitParser { onRead: function(line) { root.handleLine(line) } }
    onExited: if (root.status === "downloading") { root.status = "error"; root.errorText = "Download stopped" }
  }

  // Prefill the field with a link from the clipboard.
  Process {
    id: clipProc
    running: false
    command: ["wl-paste", "--no-newline", "--type", "text"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = text.trim()
        if (urlField.text === "" && /^https?:\/\/\S+$/i.test(t)) urlField.text = t
      }
    }
  }

  onOpenedChanged: if (opened && !busy && status !== "done" && status !== "ready") clipProc.running = true

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.status === "downloading" ? "󰇚 " + Math.floor(root.percent) + "%" : "󰇚"
    tooltipText: root.status === "downloading" ? "Downloading " + root.activeLabel + " · " + Math.floor(root.percent) + "%" : "Video downloader"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: root.status === "ready" ? keyCatcher : urlField
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: urlField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (root.status !== "ready" || dy === 0) return
        if (dy < 0 && root.selectedIndex === 0) { urlField.forceActiveFocus(); return }
        root.selectedIndex = Math.max(0, Math.min(root.options.length - 1, root.selectedIndex + dy))
      }
      onActivateRequested: if (root.status === "ready") root.startDownload(root.selectedIndex)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: panelColumn
        width: parent.width
        spacing: Style.space(10)

        // ---------- Header ----------
        Row {
          spacing: Style.space(14)
          Text {
            text: "󰇚"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.verticalCenter: parent.verticalCenter
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              text: "Video Downloader"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              text: "YOUTUBE · X · INSTAGRAM · TIKTOK · 1000+ SITES"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
          }
        }

        // ---------- Link field ----------
        Row {
          width: parent.width
          spacing: Style.space(6)

          TextField {
            id: urlField
            width: parent.width - fetchButton.width - parent.spacing
            enabled: !root.busy
            placeholderText: "Paste a video link…"
            foreground: root.bar.foreground
            font.family: root.bar.fontFamily
            selectByMouse: true
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.fetchInfo(); event.accepted = true }
              else if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
              else if (event.key === Qt.Key_Down && root.status === "ready") { keyCatcher.forceActiveFocus(); event.accepted = true }
            }
          }

          PanelActionButton {
            id: fetchButton
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.status === "loading" ? "󰑓" : "󰁔"
            tooltipText: "Find resolutions (Enter)"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            enabled: !root.busy
            onClicked: root.fetchInfo()
          }
        }

        Text {
          visible: root.status === "loading"
          width: parent.width
          text: "Looking up the video…"
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          visible: root.status === "error"
          width: parent.width
          text: "󰀦  " + root.errorText
          color: "#ed8796"
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
        }

        // ---------- Video card ----------
        Row {
          visible: root.info !== null
          width: parent.width
          spacing: Style.space(12)

          Image {
            id: thumb
            width: Style.space(120)
            height: Style.space(68)
            source: root.info ? root.info.thumbnail : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 240
            clip: true
          }

          Column {
            width: parent.width - thumb.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(3)
            Text {
              width: parent.width
              text: root.info ? root.info.title : ""
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              wrapMode: Text.Wrap
              maximumLineCount: 2
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              text: root.info ? [root.info.uploader, root.info.duration ? root.humanTime(root.info.duration) : ""].filter(function(s) { return s }).join("  ·  ") : ""
              color: Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        PanelSeparator { visible: root.info !== null; foreground: root.bar.foreground }

        // ---------- Resolutions ----------
        Flickable {
          visible: root.status === "ready" || root.status === "error" && root.options.length > 0
          width: parent.width
          height: Math.min(optionsColumn.implicitHeight, Style.space(320))
          contentHeight: optionsColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: optionsColumn
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              model: root.options

              Rectangle {
                id: opt
                required property var modelData
                required property int index
                readonly property bool selected: index === root.selectedIndex

                width: parent.width
                height: Style.space(36)
                radius: Style.cornerRadius
                color: selected ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12) : "transparent"

                Text {
                  id: optIcon
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: opt.modelData.quality === "audio" ? "󰝚" : "󰕧"
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  id: optLabel
                  anchors.left: optIcon.right
                  anchors.leftMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: opt.modelData.label
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
                Rectangle {
                  visible: opt.modelData.tag !== ""
                  anchors.left: optLabel.right
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  width: tagText.implicitWidth + Style.space(10)
                  height: tagText.implicitHeight + Style.space(2)
                  radius: Style.cornerRadius
                  color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.1)
                  Text {
                    id: tagText
                    anchors.centerIn: parent
                    text: opt.modelData.tag
                    color: Qt.darker(root.bar.foreground, 1.2)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
                Text {
                  anchors.right: dlIcon.left
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: opt.modelData.detail ? "~" + opt.modelData.detail : ""
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  id: dlIcon
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "󰇚"
                  color: root.bar.foreground
                  opacity: opt.selected ? 1 : 0.35
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.selectedIndex = opt.index
                  onClicked: root.startDownload(opt.index)
                }
              }
            }
          }
        }

        // ---------- Progress ----------
        Column {
          visible: root.status === "downloading" || root.status === "done"
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            implicitHeight: progressLabel.implicitHeight
            Text {
              id: progressLabel
              anchors.left: parent.left
              text: root.status === "done" ? "󰄬  Saved " + root.activeLabel
                  : root.stage !== "" ? root.stage + "…"
                  : "Downloading " + root.activeLabel + "  ·  " + root.percent.toFixed(1) + "%"
              color: root.status === "done" ? "#a6da95" : root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              anchors.right: parent.right
              visible: root.status === "downloading" && root.stage === ""
              text: [root.speed, root.eta ? root.eta + " left" : ""].filter(function(s) { return s }).join("  ·  ")
              color: Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(6)
            radius: height / 2
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
            Rectangle {
              width: parent.width * Math.min(1, root.percent / 100)
              height: parent.height
              radius: parent.radius
              color: root.status === "done" ? "#a6da95" : Color.accent
              Behavior on width { NumberAnimation { duration: 200 } }
            }
          }

          Text {
            visible: root.status === "done"
            width: parent.width
            text: root.doneFile.split("/").pop()
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
          }

          Row {
            spacing: Style.space(6)
            PanelActionButton {
              visible: root.status === "downloading"
              iconText: "󰜺"
              tooltipText: "Cancel download"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: root.cancelDownload()
            }
            PanelActionButton {
              visible: root.status === "done"
              iconText: "󰐊"
              tooltipText: "Play"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: { Quickshell.execDetached(["xdg-open", root.doneFile]); root.close() }
            }
            PanelActionButton {
              visible: root.status === "done"
              iconText: "󰉋"
              tooltipText: "Open folder"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: { Quickshell.execDetached(["xdg-open", root.outDir]); root.close() }
            }
            PanelActionButton {
              visible: root.status === "done"
              iconText: "󰐕"
              tooltipText: "Download another"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: root.reset()
            }
          }
        }

        Text {
          width: parent.width
          text: "Saves to " + root.outDir.replace(Quickshell.env("HOME"), "~")
          color: Qt.darker(root.bar.foreground, 1.7)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
