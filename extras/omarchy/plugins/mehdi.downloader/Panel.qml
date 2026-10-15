import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Paste a link, pick a quality and download it with yt-dlp through
// downloader.py: Best (highest resolution and bitrate), a specific height
// (highest bitrate at that height), MP3 320 kbps or the original audio.
// Every download becomes a card at the bottom with its thumbnail, progress,
// speed and time left, and can be paused, resumed, cancelled or retried.
// Up to maxParallel run at once, the rest queue; they keep running when the
// panel is closed. The list is saved to historyPath, so it survives restarts
// (paused downloads can be resumed later).
Panel {
  id: root
  moduleName: "mehdi.downloader"
  ipcTarget: "mehdi.downloader"

  readonly property string helper: decodeURIComponent(String(Qt.resolvedUrl("downloader.py")).replace(/^file:\/\//, ""))
  readonly property string outDir: (Quickshell.env("XDG_VIDEOS_DIR") || Quickshell.env("HOME") + "/Videos") + "/Downloads"
  readonly property int maxParallel: 3
  readonly property color okColor: "#a6da95"
  readonly property color errorColor: "#ed8796"
  readonly property color dimText: Qt.darker(bar.foreground, 1.45)
  readonly property string historyPath: Quickshell.env("HOME") + "/.local/state/omarchy/downloader-history.json"
  readonly property int historyLimit: 40

  // ---------- Link lookup ----------
  property string lookupStatus: "idle"   // idle | loading | ready | error
  property string lookupError: ""
  property string url: ""
  property var info: null
  property var options: []               // [{ quality, label, tag, detail }]
  property int selectedIndex: 0

  // ---------- Downloads ----------
  property var jobs: []                  // job objects, newest first
  property int jobSerial: 0

  readonly property var activeJobs: jobs.filter(function(j) { return j.phase === "running" || j.phase === "finishing" })
  readonly property int queuedCount: jobs.filter(function(j) { return j.phase === "queued" }).length
  readonly property bool hasFinished: jobs.some(function(j) { return j.finished })
  readonly property real totalSpeed: activeJobs.reduce(function(sum, j) { return sum + (j.phase === "running" ? j.speedBytes : 0) }, 0)
  readonly property real overallPercent: {
    var done = 0, total = 0
    for (var i = 0; i < activeJobs.length; i++) { done += activeJobs[i].doneBytes; total += activeJobs[i].totalBytes }
    return total > 0 ? done * 100 / total : 0
  }

  function humanSize(bytes) {
    if (!bytes) return ""
    if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " GB"
    return Math.max(1, Math.round(bytes / 1048576)) + " MB"
  }

  function humanBytes(bytes) {
    if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(2) + " GB"
    if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB"
    return Math.round(bytes / 1024) + " KB"
  }

  function humanTime(sec) {
    sec = Math.round(sec || 0)
    var h = Math.floor(sec / 3600), m = Math.floor(sec / 60) % 60, s = sec % 60
    var mm = h > 0 && m < 10 ? "0" + m : String(m)
    return (h > 0 ? h + ":" : "") + mm + ":" + (s < 10 ? "0" : "") + s
  }

  function rate(kbps) {
    if (!kbps) return ""
    return kbps >= 1000 ? (kbps / 1000).toFixed(kbps >= 10000 ? 0 : 1) + " Mbps" : kbps + " kbps"
  }

  function heightTag(h) {
    if (h >= 4320) return "8K"
    if (h >= 2160) return "4K"
    if (h >= 1440) return "2K"
    if (h >= 1080) return "FHD"
    if (h >= 720) return "HD"
    return ""
  }

  function fetchInfo() {
    var u = urlField.text.trim()
    if (!/^https?:\/\//i.test(u)) { lookupStatus = "error"; lookupError = "Paste a link that starts with http:// or https://"; return }
    if (infoProc.running) infoProc.running = false
    url = u
    info = null
    options = []
    lookupStatus = "loading"
    infoProc.command = ["python3", helper, "info", u]
    infoProc.running = true
  }

  function applyInfo(raw) {
    var d = null
    try { d = JSON.parse(raw) } catch (e) { d = { error: "Could not read yt-dlp output" } }
    if (!d || d.error) { lookupStatus = "error"; lookupError = d ? d.error : "Unknown error"; return }
    var opts = []
    if (d.hasVideo) {
      var b = d.best || {}
      opts.push({ quality: "best", label: "Best", tag: b.height ? heightTag(b.height) || b.height + "p" : "MAX",
                  detail: [b.height ? b.height + "p" + (b.fps > 30 ? b.fps : "") : "", humanSize(b.size)]
                          .filter(function(x) { return x }).join(" · ") || "highest available",
                  badge: b.height ? b.height + "p" : "Best" })
      for (var i = 0; i < d.heights.length; i++) {
        var h = d.heights[i]
        opts.push({ quality: String(h.height), label: h.height + "p" + (h.fps > 30 ? h.fps : ""), tag: heightTag(h.height),
                    detail: [rate(h.kbps), humanSize(h.size)].filter(function(x) { return x }).join(" · "),
                    badge: h.height + "p" })
      }
    }
    if (d.audio) {
      opts.push({ quality: "mp3", label: "MP3", tag: "320", detail: "320 kbps" + (d.audio.size ? " · " + humanSize(d.audio.size) : ""),
                  badge: "MP3", audio: true })
      opts.push({ quality: "audio", label: "Original", tag: (d.audio.codec || "").toUpperCase().replace("MP4A", "AAC"),
                  detail: [rate(d.audio.kbps), "no re-encode"].filter(function(x) { return x }).join(" · "),
                  badge: "AUDIO", audio: true })
    }
    info = d
    options = opts
    selectedIndex = 0
    lookupStatus = "ready"
    keyCatcher.forceActiveFocus()
  }

  // Clear the link, video card and resolutions, ready for the next link.
  function resetLookup() {
    if (infoProc.running) infoProc.running = false
    lookupStatus = "idle"; lookupError = ""; url = ""; info = null; options = []; selectedIndex = 0
    urlField.text = ""
  }

  // Open the file manager with the file selected; fall back to opening its folder.
  function revealFile(path) {
    var dir = path.substring(0, path.lastIndexOf("/"))
    var uri = "file://" + encodeURI(path)
    Quickshell.execDetached(["sh", "-c",
      'gdbus call --session --dest org.freedesktop.FileManager1 --object-path /org/freedesktop/FileManager1 '
      + '--method org.freedesktop.FileManager1.ShowItems "[\'$1\']" "" >/dev/null 2>&1 || xdg-open "$2"',
      "reveal", uri, dir])
  }

  function isQueuedOrRunning(u, quality) {
    return jobs.some(function(j) { return j.url === u && j.quality === quality && !j.finished })
  }

  function startDownload(i) {
    if (i < 0 || i >= options.length || !info) return
    var o = options[i]
    if (isQueuedOrRunning(url, o.quality)) return
    var job = jobComponent.createObject(root, {
      jobId: ++jobSerial, url: url, title: info.title, uploader: info.uploader,
      thumbnail: info.thumbnail, quality: o.quality, label: o.badge, extra: info.extra || [],
      workDir: outDir + "/.downloading-" + Date.now().toString(36) + jobSerial
    })
    jobs = [job].concat(jobs)
    pumpQueue()
  }

  function pumpQueue() {
    var running = jobs.filter(function(j) { return j.phase === "running" || j.phase === "finishing" || j.phase === "pausing" }).length
    for (var i = jobs.length - 1; i >= 0 && running < maxParallel; i--) {
      if (jobs[i].phase === "queued") { jobs[i].start(); running++ }
    }
    jobs = jobs.slice()   // refresh the derived counts
  }

  function removeJob(job) {
    if (!job.finished) job.cancel()
    jobs = jobs.filter(function(j) { return j !== job })
    job.destroy()
    pumpQueue()
  }

  function clearFinished() {
    var keep = []
    for (var i = 0; i < jobs.length; i++) {
      if (jobs[i].finished) jobs[i].destroy()
      else keep.push(jobs[i])
    }
    jobs = keep
    saveHistory()
  }

  // ---------- History: finished and paused downloads survive restarts ----------
  readonly property var savedFields: ["url", "title", "uploader", "thumbnail", "quality", "label", "extra", "workDir",
                                      "phase", "file", "error", "totalBytes", "doneBytes", "percent", "finishedAt"]

  function saveHistory() { saveTimer.restart() }

  Timer {
    id: saveTimer
    interval: 400
    onTriggered: {
      var out = []
      for (var i = 0; i < root.jobs.length && out.length < root.historyLimit; i++) {
        var j = root.jobs[i], rec = {}
        if (!(j.finished || j.phase === "paused")) continue
        for (var k = 0; k < root.savedFields.length; k++) rec[root.savedFields[k]] = j[root.savedFields[k]]
        out.push(rec)
      }
      historyFile.setText(JSON.stringify(out, null, 2) + "\n")
    }
  }

  property bool historyLoaded: false
  function loadHistory(raw) {
    if (historyLoaded) return
    historyLoaded = true
    var list = []
    try { list = JSON.parse(raw) } catch (e) { list = [] }
    if (!Array.isArray(list)) return
    var restored = []
    for (var i = 0; i < list.length; i++) {
      var rec = list[i]
      if (!rec || !rec.url) continue
      rec.jobId = ++jobSerial
      if (rec.phase === "running" || rec.phase === "finishing" || rec.phase === "queued") rec.phase = "paused"
      restored.push(jobComponent.createObject(root, rec))
    }
    jobs = jobs.concat(restored)
    checkFiles()
  }

  // Mark finished downloads whose file was moved or deleted.
  function checkFiles() {
    var done = jobs.filter(function(j) { return j.phase === "done" && j.file })
    if (done.length === 0 || fileCheck.running) return
    fileCheck.targets = done
    fileCheck.command = ["sh", "-c", 'for f; do [ -e "$f" ] && echo 1 || echo 0; done', "check"]
                        .concat(done.map(function(j) { return j.file }))
    fileCheck.running = true
  }

  Process {
    id: fileCheck
    property var targets: []
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var flags = text.trim().split("\n")
        for (var i = 0; i < fileCheck.targets.length; i++) fileCheck.targets[i].missing = flags[i] === "0"
      }
    }
  }

  FileView {
    id: historyFile
    path: root.historyPath
    printErrors: false
    onLoaded: root.loadHistory(text())
    onLoadFailed: root.loadHistory("[]")
  }

  // One download: its own helper process and progress state.
  Component {
    id: jobComponent

    Item {
      id: job
      property int jobId: 0
      property string url: ""
      property string title: ""
      property string uploader: ""
      property string thumbnail: ""
      property string quality: ""
      property string label: ""
      property var extra: []
      property string workDir: ""
      property bool missing: false
      property string finishedAt: ""

      // queued | running | pausing | paused | finishing | done | error | cancelled
      property string phase: "queued"
      onPhaseChanged: if (finished || phase === "paused") root.saveHistory()
      readonly property bool finished: phase === "done" || phase === "error" || phase === "cancelled"
      property real percent: 0
      property real shownPercent: 0
      Behavior on shownPercent { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
      onPercentChanged: shownPercent = percent
      property real doneBytes: 0
      property real totalBytes: 0
      property real speedBytes: 0
      property int etaSeconds: 0
      property int part: 0
      property int parts: 0
      property string stage: ""
      property string file: ""
      property string error: ""

      function start() {
        phase = "running"
        speedBytes = 0; etaSeconds = 0; stage = ""
        proc.command = ["python3", root.helper, "download", url, quality, root.outDir, workDir, JSON.stringify(extra || [])]
        proc.running = true
      }

      // Pause keeps the work folder (the helper sees .paused) so resume continues from there.
      function pause() {
        if (phase !== "running") return
        phase = "pausing"
        Quickshell.execDetached(["sh", "-c", 'touch "$1/.paused" && kill -TERM "$2"', "pause", workDir, String(proc.processId)])
      }

      function resume() {
        if (phase !== "paused") return
        phase = "queued"
        root.pumpQueue()
      }

      function discardWork() {
        if (workDir.indexOf("/.downloading-") > 0)
          Quickshell.execDetached(["rm", "-rf", "--", workDir])
      }

      function cancel() {
        if (phase === "running" || phase === "finishing" || phase === "pausing") { phase = "cancelled"; proc.running = false }
        else if (phase === "queued" || phase === "paused") { phase = "cancelled"; discardWork() }
      }

      function retry() {
        percent = 0; shownPercent = 0; doneBytes = 0; totalBytes = 0; speedBytes = 0
        etaSeconds = 0; part = 0; parts = 0; stage = ""; error = ""; file = ""; missing = false
        phase = "queued"
        root.pumpQueue()
      }

      function handle(line) {
        var f = String(line).trim().split(" ")
        var kind = f.shift()
        if (kind === "progress") {
          // progress <percent> <done bytes> <total bytes> <speed B/s> <eta s> <part> <parts>
          var n = f.map(Number)
          if (!isNaN(n[0])) percent = n[0]
          doneBytes = n[1] || 0
          totalBytes = n[2] || 0
          speedBytes = n[3] || 0
          etaSeconds = n[4] || 0
          part = n[5] || 0
          parts = n[6] || 0
        } else if (kind === "stage") {
          stage = f.join(" ")
          phase = "finishing"
        } else if (kind === "done") {
          file = f.join(" ")
          percent = 100
          doneBytes = totalBytes
          finishedAt = new Date().toISOString()
          phase = "done"
          if (root.url === url && !root.jobs.some(function(j) { return j.url === url && !j.finished }))
            root.resetLookup()
          Quickshell.execDetached(["notify-send", "-a", "Video Downloader", "-i", "folder-download",
                                   "Download finished", label + " · " + title])
        } else if (kind === "error") {
          error = f.join(" ")
          phase = "error"
          Quickshell.execDetached(["notify-send", "-a", "Video Downloader", "-u", "critical",
                                   "Download failed", title + "\n" + error])
        }
      }

      Process {
        id: proc
        running: false
        stdout: SplitParser { onRead: function(line) { job.handle(line) } }
        onExited: {
          if (job.phase === "pausing") { job.phase = "paused"; job.speedBytes = 0 }
          else if (job.phase === "running" || job.phase === "finishing") { job.phase = "error"; job.error = "Download stopped" }
          root.pumpQueue()
        }
      }
    }
  }

  Process {
    id: infoProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (root.lookupStatus === "loading") root.applyInfo(text)
    }
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

  onOpenedChanged: if (opened && lookupStatus === "idle") clipProc.running = true

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰇚"
    tooltipText: root.activeJobs.length === 0 ? "Video downloader"
      : (root.activeJobs.length === 1 ? "1 download" : root.activeJobs.length + " downloads")
        + " · " + Math.floor(root.overallPercent) + "%"
        + (root.queuedCount > 0 ? " · " + root.queuedCount + " queued" : "")
    onPressed: function(b) { root.toggle() }
  }

  // Overall progress under the icon while anything downloads.
  Text {
    visible: root.activeJobs.length > 0
    anchors.horizontalCenter: button.horizontalCenter
    anchors.bottom: button.bottom
    anchors.bottomMargin: Style.space(1)
    text: Math.floor(root.overallPercent) + "%"
    color: Color.accent
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.caption - 3
    font.bold: true
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: root.lookupStatus === "ready" ? keyCatcher : urlField
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: urlField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (root.lookupStatus !== "ready" || dy === 0) return
        if (dy < 0 && root.selectedIndex === 0) { urlField.forceActiveFocus(); return }
        root.selectedIndex = Math.max(0, Math.min(root.options.length - 1, root.selectedIndex + dy))
      }
      onActivateRequested: if (root.lookupStatus === "ready") root.startDownload(root.selectedIndex)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: panelColumn
        width: parent.width
        spacing: Style.space(10)

        // ---------- Header ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(headerIcon.implicitHeight, folderButton.height)

          Text {
            id: headerIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "󰇚"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
          }
          Text {
            anchors.left: headerIcon.right
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: "Video Downloader"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
          PanelActionButton {
            id: folderButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰉋"
            tooltipText: "Open " + root.outDir.replace(Quickshell.env("HOME"), "~")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: { Quickshell.execDetached(["xdg-open", root.outDir]); root.close() }
          }
        }

        // ---------- Link field ----------
        Row {
          width: parent.width
          spacing: Style.space(6)

          TextField {
            id: urlField
            width: parent.width - fetchButton.width - parent.spacing
            enabled: root.lookupStatus !== "loading"
            placeholderText: "Paste a video link…"
            foreground: root.bar.foreground
            font.family: root.bar.fontFamily
            selectByMouse: true
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.fetchInfo(); event.accepted = true }
              else if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
              else if (event.key === Qt.Key_Down && root.lookupStatus === "ready") { keyCatcher.forceActiveFocus(); event.accepted = true }
            }
          }

          PanelActionButton {
            id: fetchButton
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.lookupStatus === "loading" ? "󰑓" : "󰁔"
            tooltipText: "Find resolutions (Enter)"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            enabled: root.lookupStatus !== "loading"
            onClicked: root.fetchInfo()
          }
        }

        Text {
          visible: root.lookupStatus === "loading"
          width: parent.width
          text: "Looking up the video…"
          color: root.dimText
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          visible: root.lookupStatus === "error"
          width: parent.width
          text: "󰀦  " + root.lookupError
          color: root.errorColor
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
        }

        // ---------- Video card ----------
        Row {
          visible: root.lookupStatus === "ready" && root.info !== null
          width: parent.width
          spacing: Style.space(12)

          Rectangle {
            width: Style.space(120)
            height: Style.space(68)
            radius: Style.cornerRadius
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08)
            clip: true
            Image {
              anchors.fill: parent
              source: root.info ? root.info.thumbnail : ""
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              sourceSize.width: 240
            }
          }

          Column {
            width: parent.width - Style.space(120) - parent.spacing
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
              text: root.info ? [root.info.uploader, root.info.duration ? root.humanTime(root.info.duration) : ""]
                                  .filter(function(s) { return s }).join("  ·  ") : ""
              color: root.dimText
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        // ---------- Resolutions: a grid of chips ----------
        Flow {
          visible: root.lookupStatus === "ready"
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.options

            Rectangle {
              id: chip
              required property var modelData
              required property int index
              readonly property bool selected: index === root.selectedIndex
              readonly property bool taken: root.isQueuedOrRunning(root.url, modelData.quality) && root.jobs.length >= 0

              width: (parent.width - Style.space(6) * 2) / 3
              height: Style.space(48)
              radius: Style.cornerRadius
              color: selected ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.14)
                              : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.05)
              border.width: selected ? 1 : 0
              border.color: Color.accent
              opacity: taken ? 0.45 : 1

              Column {
                anchors.centerIn: parent
                spacing: Style.space(2)
                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: Style.space(6)
                  Text {
                    text: (chip.modelData.audio ? "󰝚 " : chip.modelData.quality === "best" ? "󰓎 " : "") + chip.modelData.label
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                  Text {
                    visible: chip.modelData.tag !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.modelData.tag
                    color: Color.accent
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption - 1
                    font.bold: true
                  }
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: chip.taken ? "downloading" : chip.modelData.detail ? "~" + chip.modelData.detail : "size unknown"
                  color: root.dimText
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: chip.taken ? Qt.ArrowCursor : Qt.PointingHandCursor
                onEntered: root.selectedIndex = chip.index
                onClicked: root.startDownload(chip.index)
              }
            }
          }
        }

        // ---------- Downloads ----------
        Item {
          visible: root.jobs.length > 0
          width: parent.width
          implicitHeight: Math.max(downloadsTitle.implicitHeight, clearButton.height)

          Text {
            id: downloadsTitle
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "DOWNLOADS" + (root.activeJobs.length > 0 ? "  ·  " + root.activeJobs.length + " ACTIVE" : "")
                  + (root.queuedCount > 0 ? "  ·  " + root.queuedCount + " QUEUED" : "")
                  + (root.totalSpeed > 0 ? "  ·  " + root.humanBytes(root.totalSpeed).toUpperCase() + "/S" : "")
            color: root.dimText
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
          }
          PanelActionButton {
            id: clearButton
            visible: root.hasFinished
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰎟"
            tooltipText: "Clear finished"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.clearFinished()
          }
        }

        Flickable {
          visible: root.jobs.length > 0
          width: parent.width
          height: Math.min(jobsColumn.implicitHeight, Style.space(400))
          contentHeight: jobsColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: jobsColumn
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: root.jobs

              Rectangle {
                id: card
                required property var modelData
                readonly property var job: modelData
                readonly property color stateColor: job.phase === "done" ? root.okColor
                                                  : job.phase === "error" ? root.errorColor
                                                  : job.phase === "paused" || job.phase === "pausing" ? root.dimText
                                                  : Color.accent

                width: parent.width
                height: cardRow.implicitHeight + Style.space(20)
                radius: Style.cornerRadius
                color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.06)

                Row {
                  id: cardRow
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.margins: Style.space(10)
                  spacing: Style.space(12)

                  // Thumbnail with the quality badge.
                  Rectangle {
                    id: cardThumb
                    width: Style.space(104)
                    height: Style.space(58)
                    radius: Style.cornerRadius
                    clip: true
                    color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08)
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                      anchors.fill: parent
                      source: card.job.thumbnail
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: true
                      sourceSize.width: 208
                      opacity: card.job.phase === "cancelled" ? 0.4 : 1
                    }
                    Rectangle {
                      anchors.right: parent.right
                      anchors.bottom: parent.bottom
                      anchors.margins: Style.space(4)
                      width: badge.implicitWidth + Style.space(8)
                      height: badge.implicitHeight + Style.space(2)
                      radius: Style.cornerRadius
                      color: Qt.rgba(0, 0, 0, 0.7)
                      Text {
                        id: badge
                        anchors.centerIn: parent
                        text: card.job.label
                        color: "white"
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption - 1
                        font.bold: true
                      }
                    }
                  }

                  Column {
                    width: cardRow.width - cardThumb.width - actions.width - cardRow.spacing * 2
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(5)

                    // Title + percentage
                    Item {
                      width: parent.width
                      implicitHeight: cardTitle.implicitHeight
                      Text {
                        id: cardTitle
                        anchors.left: parent.left
                        anchors.right: cardPercent.left
                        anchors.rightMargin: Style.space(8)
                        text: card.job.title
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                        elide: Text.ElideRight
                      }
                      Text {
                        id: cardPercent
                        anchors.right: parent.right
                        text: card.job.phase === "done" ? "100%"
                            : card.job.phase === "queued" && card.job.percent === 0 || card.job.phase === "cancelled" || card.job.phase === "error" ? ""
                            : card.job.shownPercent.toFixed(1) + "%"
                        color: card.stateColor
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                      }
                    }

                    // Progress bar
                    Rectangle {
                      id: cardTrack
                      width: parent.width
                      height: Style.space(6)
                      radius: height / 2
                      clip: true
                      color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
                      Rectangle {
                        width: parent.width * Math.min(1, (card.job.phase === "done" ? 100 : card.job.shownPercent) / 100)
                        height: parent.height
                        radius: parent.radius
                        color: card.stateColor
                        visible: card.job.phase !== "cancelled"
                      }
                      Rectangle {
                        id: shimmer
                        visible: card.job.phase === "finishing" || card.job.phase === "running" && card.job.totalBytes === 0
                        width: parent.width * 0.3
                        height: parent.height
                        radius: parent.radius
                        color: Qt.rgba(1, 1, 1, 0.35)
                        NumberAnimation on x {
                          running: shimmer.visible
                          from: -cardTrack.width * 0.3; to: cardTrack.width
                          duration: 1100; loops: Animation.Infinite
                        }
                      }
                    }

                    // Status line: bytes · part on the left, speed · time left on the right
                    Item {
                      width: parent.width
                      implicitHeight: statusLeft.implicitHeight
                      Text {
                        id: statusLeft
                        anchors.left: parent.left
                        anchors.right: statusRight.left
                        anchors.rightMargin: Style.space(8)
                        elide: Text.ElideRight
                        text: {
                          var j = card.job
                          if (j.phase === "queued") return j.percent > 0 ? "Resuming…" : "Waiting for a free slot…"
                          if (j.phase === "pausing") return "Pausing…"
                          if (j.phase === "paused") return "Paused" + (j.totalBytes > 0 ? "  ·  " + root.humanBytes(j.doneBytes) + " / " + root.humanBytes(j.totalBytes) : "")
                          if (j.phase === "cancelled") return "Cancelled"
                          if (j.phase === "error") return j.error
                          if (j.phase === "done") return j.missing ? "File moved or deleted"
                                                   : (j.totalBytes > 0 ? root.humanBytes(j.totalBytes) + "  ·  " : "") + "Saved"
                          if (j.phase === "finishing") return j.stage.charAt(0).toUpperCase() + j.stage.slice(1) + "…"
                          if (j.totalBytes === 0) return "Starting…"
                          return root.humanBytes(j.doneBytes) + " / " + root.humanBytes(j.totalBytes)
                                 + (j.parts > 1 ? "  ·  " + (j.part === 1 ? "video" : "audio") + " " + j.part + "/" + j.parts : "")
                        }
                        color: card.job.phase === "error" || card.job.missing ? root.errorColor : root.dimText
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                      Text {
                        id: statusRight
                        anchors.right: parent.right
                        visible: card.job.phase === "running" && card.job.totalBytes > 0
                        text: [card.job.speedBytes > 0 ? root.humanBytes(card.job.speedBytes) + "/s" : "",
                               card.job.etaSeconds > 0 ? root.humanTime(card.job.etaSeconds) + " left" : ""]
                              .filter(function(s) { return s }).join("  ·  ")
                        color: root.dimText
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }

                  // Actions
                  Row {
                    id: actions
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    PanelActionButton {
                      visible: card.job.phase === "running" || card.job.phase === "paused"
                      iconText: card.job.phase === "paused" ? "󰐊" : "󰏤"
                      tooltipText: card.job.phase === "paused" ? "Resume" : "Pause"
                      foreground: root.bar.foreground
                      fontFamily: root.bar.fontFamily
                      onClicked: card.job.phase === "paused" ? card.job.resume() : card.job.pause()
                    }
                    PanelActionButton {
                      visible: card.job.phase === "done" && !card.job.missing
                      iconText: "󰐊"
                      tooltipText: "Play"
                      foreground: root.bar.foreground
                      fontFamily: root.bar.fontFamily
                      onClicked: { Quickshell.execDetached(["xdg-open", card.job.file]); root.close() }
                    }
                    PanelActionButton {
                      visible: card.job.phase === "done" && !card.job.missing
                      iconText: "󰉋"
                      tooltipText: "Show in folder"
                      foreground: root.bar.foreground
                      fontFamily: root.bar.fontFamily
                      onClicked: { root.revealFile(card.job.file); root.close() }
                    }
                    PanelActionButton {
                      visible: card.job.phase === "error" || card.job.phase === "cancelled"
                      iconText: "󰑐"
                      tooltipText: "Retry"
                      foreground: root.bar.foreground
                      fontFamily: root.bar.fontFamily
                      onClicked: card.job.retry()
                    }
                    PanelActionButton {
                      iconText: card.job.finished ? "󰅖" : "󰜺"
                      tooltipText: card.job.finished ? "Remove from list" : "Cancel"
                      foreground: root.bar.foreground
                      fontFamily: root.bar.fontFamily
                      onClicked: card.job.finished ? root.removeJob(card.job) : card.job.cancel()
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
