import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Video Downloader: paste a link, pick a quality and download it with yt-dlp
// through downloader.py.
//
// - A video offers Best (highest resolution and bitrate), each height (highest
//   bitrate at that height), MP3 320 kbps or the original audio, plus subtitle
//   languages saved as separate .srt files.
// - A playlist or channel lists its videos to tick, then downloads them all in
//   one quality.
// - Every download is a card with its thumbnail, progress, speed and time left;
//   it can be paused, resumed, cancelled or retried, and a finished video can be
//   shrunk for Discord / WhatsApp or turned into a GIF.
// - Warns before re-downloading something you already have, or a download that
//   won't fit on the disk, and offers a yt-dlp update when an old one is the
//   likely cause of a failure.
// - Settings (folder, parallel downloads, default quality, speed limit,
//   subtitle languages) and the download list are saved and survive restarts.
Panel {
  id: root
  moduleName: "mehdi.downloader"
  ipcTarget: "mehdi.downloader"

  readonly property string helper: decodeURIComponent(String(Qt.resolvedUrl("downloader.py")).replace(/^file:\/\//, ""))
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy"
  readonly property string historyPath: stateDir + "/downloader-history.json"
  readonly property string settingsPath: stateDir + "/downloader-settings.json"
  readonly property int historyLimit: 60
  readonly property color okColor: "#a6da95"
  readonly property color warnColor: "#eed49f"
  readonly property color errorColor: "#ed8796"
  readonly property color dimText: Qt.darker(bar.foreground, 1.45)
  readonly property color fg: bar.foreground

  function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a) }

  // ---------- Settings ----------
  readonly property string defaultFolder: (Quickshell.env("XDG_VIDEOS_DIR") || home + "/Videos") + "/Downloads"
  property var settings: ({ folder: defaultFolder, maxParallel: 3, defaultQuality: "best", rate: "", subLangs: ["tr", "en"] })
  readonly property string outDir: settings.folder || defaultFolder
  readonly property int maxParallel: settings.maxParallel || 3

  function setSetting(key, value) {
    var s = Object.assign({}, settings)
    s[key] = value
    settings = s
    settingsFile.setText(JSON.stringify(settings, null, 2) + "\n")
    if (key === "maxParallel") pumpQueue()
    if (key === "folder") refreshSpace()
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    printErrors: false
    onLoaded: {
      try { root.settings = Object.assign({}, root.settings, JSON.parse(text())) } catch (e) {}
      root.refreshSpace()
    }
    onLoadFailed: root.refreshSpace()
  }

  // ---------- Views ----------
  property bool showSettings: false

  // ---------- Link lookup ----------
  property string lookupStatus: "idle"   // idle | loading | ready | error
  property string lookupError: ""
  property int lookupOutdated: 0
  property string url: ""
  property var info: null                // single video
  property var playlist: null            // playlist / channel
  property var options: []               // [{ quality, label, tag, detail, badge, audio, size }]
  property int selectedIndex: 0
  property var subChoices: []            // [{ code, label, auto }]
  property var subSelected: []           // codes
  property var picked: []                // playlist: selected entry indexes
  property string playlistQuality: "best"

  // Confirmation strip: { kind: "exists" | "space", text, index, job }
  property var confirm: null

  // ---------- Downloads ----------
  property var jobs: []                  // job objects, newest first
  property int jobSerial: 0

  readonly property var activeJobs: jobs.filter(function(j) { return j.phase === "running" || j.phase === "finishing" || j.phase === "pausing" })
  readonly property int queuedCount: jobs.filter(function(j) { return j.phase === "queued" }).length
  readonly property bool hasFinished: jobs.some(function(j) { return j.finished })
  readonly property real totalSpeed: activeJobs.reduce(function(sum, j) { return sum + (j.phase === "running" ? j.speedBytes : 0) }, 0)
  readonly property real overallPercent: {
    var done = 0, total = 0, pct = 0, n = 0
    for (var i = 0; i < activeJobs.length; i++) {
      var j = activeJobs[i]
      if (j.totalBytes > 0) { done += j.doneBytes; total += j.totalBytes }
      pct += j.percent; n++
    }
    return total > 0 ? done * 100 / total : n > 0 ? pct / n : 0
  }

  // ---------- Disk space ----------
  property real freeBytes: 0
  function refreshSpace() {
    if (spaceProc.running) return
    spaceProc.command = ["sh", "-c", 'd="$1"; while [ ! -d "$d" ] && [ "$d" != / ]; do d=$(dirname "$d"); done; df -B1 --output=avail "$d" | tail -1', "df", outDir]
    spaceProc.running = true
  }
  Process {
    id: spaceProc
    running: false
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.freeBytes = Number(text.trim()) || 0 }
  }
  // Space the unfinished downloads will still take.
  readonly property real pendingBytes: jobs.reduce(function(sum, j) {
    return sum + (j.kind === "download" && !j.finished && j.totalBytes > j.doneBytes ? j.totalBytes - j.doneBytes : 0)
  }, 0)

  // ---------- yt-dlp version ----------
  property string ytdlpVersion: ""
  property int ytdlpAge: 0
  Process {
    id: versionProc
    running: true
    command: ["yt-dlp", "--version"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.ytdlpVersion = text.trim()
        var p = root.ytdlpVersion.split(".").map(Number)
        if (p.length >= 3) root.ytdlpAge = Math.floor((Date.now() - new Date(p[0], p[1] - 1, p[2]).getTime()) / 86400000)
      }
    }
  }
  function updateYtdlp() {
    root.close()
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", "omarchy update"])
  }

  // ---------- Formatting ----------
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

  readonly property var languageNames: ({
    tr: "Türkçe", en: "English", de: "Deutsch", fr: "Français", es: "Español", it: "Italiano", nl: "Nederlands",
    pt: "Português", ru: "Русский", ar: "العربية", fa: "فارسی", ja: "日本語", ko: "한국어", zh: "中文", az: "Azərbaycan"
  })
  function languageLabel(code) {
    var base = code.replace(/-orig$/, "").split("-")[0]
    return (languageNames[base] || code.toUpperCase()) + (code.indexOf("-orig") > 0 ? " (auto)" : "")
  }

  // ---------- Lookup ----------
  function fetchInfo() {
    var u = urlField.text.trim()
    if (!/^https?:\/\//i.test(u)) { lookupStatus = "error"; lookupError = "Paste a link that starts with http:// or https://"; lookupOutdated = 0; return }
    if (infoProc.running) infoProc.running = false
    url = u
    info = null; playlist = null; options = []; subChoices = []; subSelected = []; picked = []; confirm = null
    lookupStatus = "loading"
    infoProc.command = ["python3", helper, "info", u, outDir]
    infoProc.running = true
  }

  function resetLookup() {
    if (infoProc.running) infoProc.running = false
    lookupStatus = "idle"; lookupError = ""; lookupOutdated = 0; url = ""
    info = null; playlist = null; options = []; selectedIndex = 0; subChoices = []; subSelected = []; picked = []; confirm = null
    urlField.text = ""
  }

  function defaultIndex(opts) {
    var want = settings.defaultQuality || "best"
    for (var i = 0; i < opts.length; i++) if (opts[i].quality === want) return i
    if (/^\d+$/.test(want)) {     // closest height at or below the default
      for (var k = 0; k < opts.length; k++) if (/^\d+$/.test(opts[k].quality) && Number(opts[k].quality) <= Number(want)) return k
    }
    return 0
  }

  function applyInfo(raw) {
    var d = null
    try { d = JSON.parse(raw) } catch (e) { d = { error: "Could not read yt-dlp output" } }
    if (!d || d.error) { lookupStatus = "error"; lookupError = d ? d.error : "Unknown error"; lookupOutdated = d && d.outdated || 0; return }
    if (d.freeBytes) freeBytes = d.freeBytes

    if (d.playlist) {
      playlist = d
      var all = []
      for (var p = 0; p < d.entries.length; p++) all.push(p)
      picked = all
      var q = settings.defaultQuality || "best"
      playlistQuality = ["best", "2160", "1080", "720", "480", "mp3", "audio"].indexOf(q) >= 0 ? q : "best"
      lookupStatus = "ready"
      return
    }

    var opts = []
    if (d.hasVideo) {
      var b = d.best || {}
      opts.push({ quality: "best", label: "Best", tag: b.height ? heightTag(b.height) || b.height + "p" : "MAX",
                  detail: [b.height ? b.height + "p" + (b.fps > 30 ? b.fps : "") : "", humanSize(b.size)]
                          .filter(function(x) { return x }).join(" · ") || "highest available",
                  badge: b.height ? b.height + "p" : "Best", size: b.size || 0 })
      for (var i = 0; i < d.heights.length; i++) {
        var h = d.heights[i]
        opts.push({ quality: String(h.height), label: h.height + "p" + (h.fps > 30 ? h.fps : ""), tag: heightTag(h.height),
                    detail: [rate(h.kbps), humanSize(h.size)].filter(function(x) { return x }).join(" · "),
                    badge: h.height + "p", size: h.size || 0 })
      }
    }
    if (d.audio) {
      opts.push({ quality: "mp3", label: "MP3", tag: "320", detail: "320 kbps" + (d.audio.size ? " · " + humanSize(d.audio.size) : ""),
                  badge: "MP3", audio: true, size: d.audio.size || 0 })
      opts.push({ quality: "audio", label: "Original", tag: (d.audio.codec || "").toUpperCase().replace("MP4A", "AAC"),
                  detail: [rate(d.audio.kbps), "no re-encode"].filter(function(x) { return x }).join(" · "),
                  badge: "AUDIO", audio: true, size: d.audio.size || 0 })
    }

    // Subtitles: every manual track, plus the auto ones in your languages or the original language.
    var langs = (settings.subLangs || []).map(function(l) { return l.toLowerCase() })
    var choices = [], seen = {}
    function base(c) { return c.replace(/-orig$/, "").split("-")[0].toLowerCase() }
    for (var m = 0; m < (d.subtitles || []).length; m++) {
      var c = d.subtitles[m]
      if (seen[base(c)]) continue
      seen[base(c)] = true
      choices.push({ code: c, label: languageLabel(c), auto: false })
    }
    for (var a = 0; a < (d.autoSubtitles || []).length; a++) {
      var ac = d.autoSubtitles[a]
      if (seen[base(ac)]) continue
      if (ac.indexOf("-orig") < 0 && langs.indexOf(base(ac)) < 0) continue
      seen[base(ac)] = true
      choices.push({ code: ac, label: languageLabel(ac) + (ac.indexOf("-orig") < 0 ? " (auto)" : ""), auto: true })
    }
    // Your languages first.
    choices.sort(function(x, y) {
      var ix = langs.indexOf(base(x.code)), iy = langs.indexOf(base(y.code))
      return (ix < 0 ? 99 : ix) - (iy < 0 ? 99 : iy)
    })

    info = d
    options = opts
    subChoices = choices
    subSelected = []
    selectedIndex = defaultIndex(opts)
    lookupStatus = "ready"
    keyCatcher.forceActiveFocus()
  }

  function toggleSub(code) {
    var s = subSelected.slice(), i = s.indexOf(code)
    if (i >= 0) s.splice(i, 1); else s.push(code)
    subSelected = s
  }

  function togglePick(i) {
    var s = picked.slice(), k = s.indexOf(i)
    if (k >= 0) s.splice(k, 1); else s.push(i)
    picked = s.sort(function(a, b) { return a - b })
  }

  // ---------- Starting downloads ----------
  function existingJob(u, quality) {
    for (var i = 0; i < jobs.length; i++) {
      var j = jobs[i]
      if (j.kind === "download" && j.url === u && j.quality === quality && j.phase === "done" && !j.missing) return j
    }
    return null
  }

  function isQueuedOrRunning(u, quality) {
    return jobs.some(function(j) { return j.kind === "download" && j.url === u && j.quality === quality && !j.finished })
  }

  function newJob(props) {
    props.jobId = ++jobSerial
    props.workDir = outDir + "/.downloading-" + Date.now().toString(36) + jobSerial
    props.outDir = outDir
    var job = jobComponent.createObject(root, props)
    jobs = [job].concat(jobs)
    return job
  }

  // Click on a quality: check for a copy you already have and for disk space first.
  function requestDownload(i, force) {
    if (i < 0 || i >= options.length || !info) return
    var o = options[i]
    if (isQueuedOrRunning(url, o.quality)) return
    if (!force) {
      var have = existingJob(url, o.quality)
      if (have) {
        confirm = { kind: "exists", index: i, job: have, text: "You already downloaded this in " + o.badge + "." }
        return
      }
      var free = freeBytes - pendingBytes
      if (o.size && freeBytes && o.size * 1.05 > free) {
        confirm = { kind: "space", index: i,
                    text: "Needs about " + humanSize(o.size) + ", only " + humanSize(Math.max(0, free)) + " free." }
        return
      }
    }
    confirm = null
    newJob({ kind: "download", url: url, title: info.title, uploader: info.uploader, thumbnail: info.thumbnail,
             quality: o.quality, label: o.badge, extra: info.extra || [],
             subs: o.audio ? [] : subSelected.slice(), rateLimit: settings.rate || "" })
    pumpQueue()
  }

  function downloadPlaylist() {
    if (!playlist) return
    var skipped = 0, added = 0
    var label = { best: "Best", mp3: "MP3", audio: "AUDIO" }[playlistQuality] || playlistQuality + "p"
    for (var k = 0; k < picked.length; k++) {
      var e = playlist.entries[picked[k]]
      if (!e || isQueuedOrRunning(e.url, playlistQuality) || existingJob(e.url, playlistQuality)) { skipped++; continue }
      newJob({ kind: "download", url: e.url, title: e.title, uploader: e.uploader || playlist.uploader,
               thumbnail: e.thumbnail, quality: playlistQuality, label: label, extra: playlist.extra || [],
               subs: [], rateLimit: settings.rate || "" })
      added++
    }
    pumpQueue()
    if (added > 0)
      Quickshell.execDetached(["notify-send", "-a", "Video Downloader", "-i", "folder-download",
                               added + (added === 1 ? " video" : " videos") + " queued",
                               playlist.title + (skipped ? "\n" + skipped + " already downloaded, skipped" : "")])
    resetLookup()
  }

  function startShrink(source, target) {
    var label = target === "gif" ? "GIF" : target + " MB"
    newJob({ kind: "shrink", url: source.url, title: source.title, uploader: source.uploader,
             thumbnail: source.thumbnail, quality: target, label: label, source: source.file })
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
    saveHistory()
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

  // Open the file manager with the file selected; fall back to opening its folder.
  function revealFile(path) {
    var dir = path.substring(0, path.lastIndexOf("/"))
    var uri = "file://" + encodeURI(path)
    Quickshell.execDetached(["sh", "-c",
      'gdbus call --session --dest org.freedesktop.FileManager1 --object-path /org/freedesktop/FileManager1 '
      + '--method org.freedesktop.FileManager1.ShowItems "[\'$1\']" "" >/dev/null 2>&1 || xdg-open "$2"',
      "reveal", uri, dir])
  }

  // ---------- History: finished and paused downloads survive restarts ----------
  readonly property var savedFields: ["kind", "url", "title", "uploader", "thumbnail", "quality", "label", "extra", "subs",
                                      "rateLimit", "source", "workDir", "outDir", "phase", "file", "error",
                                      "totalBytes", "doneBytes", "percent", "finishedAt"]

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
      if (!rec.kind) rec.kind = "download"
      if (["running", "finishing", "queued", "pausing"].indexOf(rec.phase) >= 0)
        rec.phase = rec.kind === "download" ? "paused" : "cancelled"
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

  // ---------- One download or shrink job ----------
  Component {
    id: jobComponent

    Item {
      id: job
      property int jobId: 0
      property string kind: "download"      // download | shrink
      property string url: ""
      property string title: ""
      property string uploader: ""
      property string thumbnail: ""
      property string quality: ""
      property string label: ""
      property var extra: []
      property var subs: []
      property string rateLimit: ""
      property string source: ""            // shrink: the file to re-encode
      property string workDir: ""
      property string outDir: ""
      property bool missing: false
      property string finishedAt: ""
      property bool shrinkOpen: false
      property int outdated: 0

      // queued | running | pausing | paused | finishing | done | error | cancelled
      property string phase: "queued"
      readonly property bool finished: phase === "done" || phase === "error" || phase === "cancelled"
      readonly property bool isVideoFile: phase === "done" && /\.(mp4|mkv|webm|mov)$/i.test(file)
      onPhaseChanged: if (finished || phase === "paused") root.saveHistory()
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
        speedBytes = 0; etaSeconds = 0; stage = ""; outdated = 0
        if (kind === "shrink") {
          proc.command = ["python3", root.helper, "shrink", source, quality]
        } else {
          proc.command = ["python3", root.helper, "download", url, quality, outDir || root.outDir, workDir,
                          JSON.stringify(extra || []), JSON.stringify({ subs: subs || [], rate: rateLimit || "" })]
        }
        proc.running = true
      }

      // Pause keeps the work folder (the helper sees .paused) so resume continues from there.
      function pause() {
        if (phase !== "running" || kind !== "download") return
        phase = "pausing"
        Quickshell.execDetached(["sh", "-c", 'touch "$1/.paused" && kill -TERM "$2"', "pause", workDir, String(proc.processId)])
      }

      function resume() {
        if (phase !== "paused") return
        phase = "queued"
        root.pumpQueue()
      }

      function discardWork() {
        if (workDir.indexOf("/.downloading-") > 0) Quickshell.execDetached(["rm", "-rf", "--", workDir])
      }

      function cancel() {
        if (phase === "running" || phase === "finishing" || phase === "pausing") { phase = "cancelled"; proc.running = false }
        else if (phase === "queued" || phase === "paused") { phase = "cancelled"; discardWork() }
      }

      function retry() {
        percent = 0; shownPercent = 0; doneBytes = 0; totalBytes = 0; speedBytes = 0
        etaSeconds = 0; part = 0; parts = 0; stage = ""; error = ""; file = ""; missing = false; outdated = 0
        phase = "queued"
        root.pumpQueue()
      }

      function handle(line) {
        var f = String(line).trim().split(" ")
        var what = f.shift()
        if (what === "progress") {
          // progress <percent> <done bytes> <total bytes> <speed B/s> <eta s> <part> <parts>
          var n = f.map(Number)
          if (!isNaN(n[0])) percent = n[0]
          doneBytes = n[1] || 0
          totalBytes = n[2] || 0
          speedBytes = n[3] || 0
          etaSeconds = n[4] || 0
          part = n[5] || 0
          parts = n[6] || 0
        } else if (what === "stage") {
          stage = f.join(" ")
          if (kind === "download") phase = "finishing"
        } else if (what === "done") {
          file = f.join(" ")
          percent = 100
          doneBytes = totalBytes
          finishedAt = new Date().toISOString()
          phase = "done"
          root.refreshSpace()
          Quickshell.execDetached(["notify-send", "-a", "Video Downloader", "-i", "folder-download",
                                   kind === "shrink" ? "Ready to share" : "Download finished", label + " · " + title])
          if (kind === "download" && root.url === url && !root.jobs.some(function(j) { return j.url === url && !j.finished }))
            root.resetLookup()
        } else if (what === "outdated") {
          outdated = Number(f[0]) || 0
        } else if (what === "error") {
          error = f.join(" ")
          phase = "error"
          Quickshell.execDetached(["notify-send", "-a", "Video Downloader", "-u", "critical",
                                   kind === "shrink" ? "Shrinking failed" : "Download failed", title + "\n" + error])
        }
      }

      Process {
        id: proc
        running: false
        stdout: SplitParser { onRead: function(line) { job.handle(line) } }
        onExited: {
          if (job.phase === "pausing") { job.phase = "paused"; job.speedBytes = 0 }
          else if (job.phase === "running" || job.phase === "finishing") { job.phase = "error"; job.error = "Stopped unexpectedly" }
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

  onOpenedChanged: if (opened) {
    refreshSpace()
    checkFiles()
    if (lookupStatus === "idle") clipProc.running = true
  }

  // ---------- Reusable pieces ----------

  // A selectable tile: quality, subtitle language, setting value.
  component Chip: Rectangle {
    id: chip
    property string text: ""
    property string tag: ""
    property string sub: ""
    property bool selected: false
    property bool muted: false
    property bool compact: false
    signal clicked()
    signal hoveredIn()

    height: compact ? Style.space(28) : Style.space(48)
    radius: Style.cornerRadius
    color: selected ? root.tint(0.16) : chipMouse.containsMouse ? root.tint(0.1) : root.tint(0.05)
    border.width: selected ? 1 : 0
    border.color: Color.accent
    opacity: muted ? 0.45 : 1

    Column {
      anchors.centerIn: parent
      spacing: Style.space(2)
      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(6)
        Text {
          text: chip.text
          color: root.fg
          font.family: root.bar.fontFamily
          font.pixelSize: chip.compact ? Style.font.caption + 1 : Style.font.body
          font.bold: true
        }
        Text {
          visible: chip.tag !== ""
          anchors.verticalCenter: parent.verticalCenter
          text: chip.tag
          color: Color.accent
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption - 1
          font.bold: true
        }
      }
      Text {
        visible: chip.sub !== "" && !chip.compact
        anchors.horizontalCenter: parent.horizontalCenter
        text: chip.sub
        color: root.dimText
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: chip.muted ? Qt.ArrowCursor : Qt.PointingHandCursor
      onEntered: chip.hoveredIn()
      onClicked: chip.clicked()
    }
  }

  // Small caps section label.
  component SectionLabel: Text {
    color: root.dimText
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.2
  }

  // Text button, for confirmations and the playlist action.
  component TextButton: Rectangle {
    id: tb
    property string text: ""
    property bool primary: false
    signal clicked()
    width: tbText.implicitWidth + Style.space(20)
    height: Style.space(28)
    radius: Style.cornerRadius
    color: primary ? Color.accent : tbMouse.containsMouse ? root.tint(0.14) : root.tint(0.07)
    Text {
      id: tbText
      anchors.centerIn: parent
      text: tb.text
      color: tb.primary ? Color.background : root.fg
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption + 1
      font.bold: true
    }
    MouseArea { id: tbMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tb.clicked() }
  }

  // ---------- Bar icon ----------
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

  // Overall progress under the icon while anything runs.
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

  // ---------- Panel ----------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: root.lookupStatus === "ready" && !root.showSettings ? keyCatcher : urlField
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(820))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: urlField.activeFocus || folderField.activeFocus || langField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (root.lookupStatus !== "ready" || !root.info || root.showSettings) return
        var cols = 3, n = root.options.length, i = root.selectedIndex
        if (dx !== 0) i = Math.max(0, Math.min(n - 1, i + dx))
        if (dy !== 0) {
          if (dy < 0 && i < cols) { urlField.forceActiveFocus(); return }
          i = Math.max(0, Math.min(n - 1, i + dy * cols))
        }
        root.selectedIndex = i
      }
      onActivateRequested: if (root.lookupStatus === "ready" && root.info && !root.showSettings) root.requestDownload(root.selectedIndex, false)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: panelColumn
        width: parent.width
        spacing: Style.space(10)

        // ---------- Header ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(headerIcon.implicitHeight, settingsButton.height)

          Text {
            id: headerIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.showSettings ? "󰒓" : "󰇚"
            color: root.fg
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
          }
          Text {
            anchors.left: headerIcon.right
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: root.showSettings ? "Settings" : "Video Downloader"
            color: root.fg
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            PanelActionButton {
              visible: !root.showSettings
              iconText: "󰉋"
              tooltipText: "Open " + root.outDir.replace(root.home, "~")
              foreground: root.fg
              fontFamily: root.bar.fontFamily
              onClicked: { Quickshell.execDetached(["xdg-open", root.outDir]); root.close() }
            }
            PanelActionButton {
              id: settingsButton
              iconText: root.showSettings ? "󰁍" : "󰒓"
              tooltipText: root.showSettings ? "Back" : "Settings"
              foreground: root.fg
              fontFamily: root.bar.fontFamily
              onClicked: root.showSettings = !root.showSettings
            }
          }
        }

        // =====================================================================
        // Settings view
        // =====================================================================
        Column {
          visible: root.showSettings
          width: parent.width
          spacing: Style.space(14)

          Column {
            width: parent.width
            spacing: Style.space(6)
            SectionLabel { text: "SAVE TO" }
            TextField {
              id: folderField
              width: parent.width
              text: root.outDir.replace(root.home, "~")
              foreground: root.fg
              font.family: root.bar.fontFamily
              selectByMouse: true
              onEditingFinished: {
                var t = text.trim().replace(/^~/, root.home).replace(/\/+$/, "")
                if (t !== "" && t !== root.outDir) root.setSetting("folder", t)
              }
            }
            Text {
              text: root.freeBytes > 0 ? root.humanSize(root.freeBytes) + " free on this disk" : ""
              color: root.freeBytes > 0 && root.freeBytes < 10737418240 ? root.warnColor : root.dimText
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            SectionLabel { text: "DOWNLOADS AT ONCE" }
            Row {
              spacing: Style.space(6)
              Repeater {
                model: [1, 2, 3, 4, 5]
                Chip {
                  required property var modelData
                  compact: true
                  width: Style.space(44)
                  text: String(modelData)
                  selected: root.maxParallel === modelData
                  onClicked: root.setSetting("maxParallel", modelData)
                }
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            SectionLabel { text: "DEFAULT QUALITY" }
            Flow {
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: [["best", "Best"], ["2160", "4K"], ["1080", "1080p"], ["720", "720p"], ["480", "480p"], ["mp3", "MP3"]]
                Chip {
                  required property var modelData
                  compact: true
                  width: Style.space(66)
                  text: modelData[1]
                  selected: (root.settings.defaultQuality || "best") === modelData[0]
                  onClicked: root.setSetting("defaultQuality", modelData[0])
                }
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            SectionLabel { text: "SPEED LIMIT (PER DOWNLOAD)" }
            Flow {
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: [["", "No limit"], ["1M", "1 MB/s"], ["5M", "5 MB/s"], ["10M", "10 MB/s"], ["25M", "25 MB/s"]]
                Chip {
                  required property var modelData
                  compact: true
                  width: Style.space(78)
                  text: modelData[1]
                  selected: (root.settings.rate || "") === modelData[0]
                  onClicked: root.setSetting("rate", modelData[0])
                }
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            SectionLabel { text: "SUBTITLE LANGUAGES" }
            TextField {
              id: langField
              width: parent.width
              text: (root.settings.subLangs || []).join(", ")
              placeholderText: "tr, en"
              foreground: root.fg
              font.family: root.bar.fontFamily
              selectByMouse: true
              onEditingFinished: root.setSetting("subLangs", text.split(/[\s,]+/).map(function(s) { return s.trim().toLowerCase() })
                                                                  .filter(function(s) { return /^[a-z]{2,3}$/.test(s) }))
            }
            Text {
              width: parent.width
              text: "Language codes, first is preferred. Offered when a video has them, saved as .srt next to the video."
              color: root.dimText
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(versionText.implicitHeight, updateButton.height)
            Column {
              id: versionText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              SectionLabel { text: "YT-DLP" }
              Text {
                text: root.ytdlpVersion ? root.ytdlpVersion + "  ·  " + (root.ytdlpAge === 0 ? "released today" : root.ytdlpAge + " days old") : "not found"
                color: root.ytdlpAge >= 30 ? root.warnColor : root.dimText
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            TextButton {
              id: updateButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "󰚰  Update system"
              onClicked: root.updateYtdlp()
            }
          }
        }

        // =====================================================================
        // Main view
        // =====================================================================

        // ---------- Link field ----------
        Row {
          visible: !root.showSettings
          width: parent.width
          spacing: Style.space(6)

          TextField {
            id: urlField
            width: parent.width - fetchButton.width - parent.spacing
            enabled: root.lookupStatus !== "loading"
            placeholderText: "Paste a video, playlist or channel link…"
            foreground: root.fg
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
            tooltipText: "Look it up (Enter)"
            foreground: root.fg
            fontFamily: root.bar.fontFamily
            enabled: root.lookupStatus !== "loading"
            onClicked: root.fetchInfo()
          }
        }

        Text {
          visible: !root.showSettings && root.lookupStatus === "loading"
          width: parent.width
          text: "Looking it up…"
          color: root.dimText
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
        }

        // Lookup error, with an update offer when an old yt-dlp is the likely cause.
        Column {
          visible: !root.showSettings && root.lookupStatus === "error"
          width: parent.width
          spacing: Style.space(6)
          Text {
            width: parent.width
            text: "󰀦  " + root.lookupError
            color: root.errorColor
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
          }
          Row {
            visible: root.lookupOutdated > 0
            spacing: Style.space(8)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "yt-dlp is " + root.lookupOutdated + " days old; sites change and newer versions fix this."
              color: root.warnColor
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
            TextButton { text: "󰚰  Update"; onClicked: root.updateYtdlp() }
          }
        }

        // ---------- Single video ----------
        Row {
          visible: !root.showSettings && root.lookupStatus === "ready" && root.info !== null
          width: parent.width
          spacing: Style.space(12)

          Rectangle {
            width: Style.space(120)
            height: Style.space(68)
            radius: Style.cornerRadius
            color: root.tint(0.08)
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
              color: root.fg
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

        Flow {
          visible: !root.showSettings && root.lookupStatus === "ready" && root.info !== null
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.options
            Chip {
              required property var modelData
              required property int index
              width: (parent.width - Style.space(6) * 2) / 3
              text: (modelData.audio ? "󰝚 " : modelData.quality === "best" ? "󰓎 " : "") + modelData.label
              tag: modelData.tag
              sub: root.isQueuedOrRunning(root.url, modelData.quality) ? "downloading"
                 : root.existingJob(root.url, modelData.quality) ? "󰄬 downloaded"
                 : modelData.detail || "size unknown"
              selected: index === root.selectedIndex
              muted: root.isQueuedOrRunning(root.url, modelData.quality)
              onHoveredIn: root.selectedIndex = index
              onClicked: root.requestDownload(index, false)
            }
          }
        }

        // Subtitles for the next download (videos only).
        Column {
          visible: !root.showSettings && root.lookupStatus === "ready" && root.info !== null && root.subChoices.length > 0
          width: parent.width
          spacing: Style.space(6)
          SectionLabel { text: "SUBTITLES  ·  SAVED AS .SRT" + (root.subSelected.length ? "  ·  " + root.subSelected.length + " SELECTED" : "") }
          Flow {
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: root.subChoices
              Chip {
                required property var modelData
                compact: true
                width: Math.max(Style.space(70), modelData.label.length * Style.space(8) + Style.space(26))
                text: (root.subSelected.indexOf(modelData.code) >= 0 ? "󰄬 " : "") + modelData.label
                selected: root.subSelected.indexOf(modelData.code) >= 0
                onClicked: root.toggleSub(modelData.code)
              }
            }
          }
        }

        // ---------- Playlist / channel ----------
        Column {
          visible: !root.showSettings && root.lookupStatus === "ready" && root.playlist !== null
          width: parent.width
          spacing: Style.space(8)

          Row {
            width: parent.width
            spacing: Style.space(12)
            Rectangle {
              width: Style.space(96)
              height: Style.space(54)
              radius: Style.cornerRadius
              color: root.tint(0.08)
              clip: true
              Image {
                anchors.fill: parent
                source: root.playlist ? root.playlist.thumbnail : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 192
              }
            }
            Column {
              width: parent.width - Style.space(96) - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)
              Text {
                width: parent.width
                text: root.playlist ? "󰲸  " + root.playlist.title : ""
                color: root.fg
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: root.playlist ? [root.playlist.uploader, root.playlist.count + " videos"].filter(function(s) { return s }).join("  ·  ") : ""
                color: root.dimText
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }

          Item {
            width: parent.width
            implicitHeight: selectAll.height
            SectionLabel {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: root.picked.length + " OF " + (root.playlist ? root.playlist.count : 0) + " SELECTED"
            }
            TextButton {
              id: selectAll
              anchors.right: parent.right
              text: root.playlist && root.picked.length === root.playlist.count ? "Select none" : "Select all"
              onClicked: {
                if (root.picked.length === root.playlist.count) { root.picked = []; return }
                var all = []
                for (var i = 0; i < root.playlist.count; i++) all.push(i)
                root.picked = all
              }
            }
          }

          Flickable {
            width: parent.width
            height: Math.min(entriesColumn.implicitHeight, Style.space(260))
            contentHeight: entriesColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: entriesColumn
              width: parent.width
              spacing: Style.space(2)
              Repeater {
                model: root.playlist ? root.playlist.entries : []
                Rectangle {
                  id: entry
                  required property var modelData
                  required property int index
                  readonly property bool checked: root.picked.indexOf(index) >= 0
                  width: parent.width
                  height: Style.space(40)
                  radius: Style.cornerRadius
                  color: entryMouse.containsMouse ? root.tint(0.08) : "transparent"
                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(6)
                    anchors.rightMargin: Style.space(8)
                    spacing: Style.space(10)
                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: entry.checked ? "󰄲" : "󰄱"
                      color: entry.checked ? Color.accent : root.dimText
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.body + 2
                    }
                    Rectangle {
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(56)
                      height: Style.space(32)
                      radius: Style.cornerRadius / 2
                      color: root.tint(0.08)
                      clip: true
                      Image {
                        anchors.fill: parent
                        source: entry.modelData.thumbnail
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 112
                      }
                    }
                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      width: parent.width - Style.space(56) - Style.space(30) - entryLength.width - parent.spacing * 3
                      text: entry.modelData.title
                      color: root.fg
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.caption + 1
                      elide: Text.ElideRight
                    }
                    Text {
                      id: entryLength
                      anchors.verticalCenter: parent.verticalCenter
                      text: entry.modelData.duration ? root.humanTime(entry.modelData.duration) : ""
                      color: root.dimText
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                  MouseArea { id: entryMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.togglePick(entry.index) }
                }
              }
            }
          }

          SectionLabel { text: "QUALITY FOR ALL" }
          Flow {
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: [["best", "󰓎 Best"], ["2160", "4K"], ["1080", "1080p"], ["720", "720p"], ["480", "480p"], ["mp3", "󰝚 MP3"], ["audio", "󰝚 Original"]]
              Chip {
                required property var modelData
                compact: true
                width: Style.space(84)
                text: modelData[1]
                selected: root.playlistQuality === modelData[0]
                onClicked: root.playlistQuality = modelData[0]
              }
            }
          }

          TextButton {
            primary: true
            text: "󰇚  Download " + root.picked.length + (root.picked.length === 1 ? " video" : " videos")
            opacity: root.picked.length > 0 ? 1 : 0.4
            onClicked: if (root.picked.length > 0) root.downloadPlaylist()
          }
        }

        // ---------- Confirmation: already downloaded / not enough space ----------
        Rectangle {
          visible: !root.showSettings && root.confirm !== null
          width: parent.width
          height: confirmColumn.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: Qt.rgba(root.warnColor.r, root.warnColor.g, root.warnColor.b, 0.12)
          border.width: 1
          border.color: Qt.rgba(root.warnColor.r, root.warnColor.g, root.warnColor.b, 0.5)

          Column {
            id: confirmColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(10)
            spacing: Style.space(8)
            Text {
              width: parent.width
              text: (root.confirm && root.confirm.kind === "space" ? "󰋊  " : "󰄬  ") + (root.confirm ? root.confirm.text : "")
              color: root.warnColor
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.Wrap
            }
            Row {
              spacing: Style.space(6)
              TextButton {
                visible: root.confirm !== null && root.confirm.kind === "exists"
                primary: true
                text: "󰐊  Open it"
                onClicked: { Quickshell.execDetached(["xdg-open", root.confirm.job.file]); root.confirm = null; root.close() }
              }
              TextButton {
                visible: root.confirm !== null && root.confirm.kind === "exists"
                text: "󰉋  Show in folder"
                onClicked: { root.revealFile(root.confirm.job.file); root.confirm = null; root.close() }
              }
              TextButton {
                text: root.confirm && root.confirm.kind === "space" ? "Download anyway" : "Download again"
                onClicked: root.requestDownload(root.confirm.index, true)
              }
              TextButton { text: "Cancel"; onClicked: root.confirm = null }
            }
          }
        }

        // ---------- Downloads ----------
        Item {
          visible: !root.showSettings && root.jobs.length > 0
          width: parent.width
          implicitHeight: Math.max(downloadsTitle.implicitHeight, clearButton.height)

          SectionLabel {
            id: downloadsTitle
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "DOWNLOADS" + (root.activeJobs.length > 0 ? "  ·  " + root.activeJobs.length + " ACTIVE" : "")
                  + (root.queuedCount > 0 ? "  ·  " + root.queuedCount + " QUEUED" : "")
                  + (root.totalSpeed > 0 ? "  ·  " + root.humanBytes(root.totalSpeed).toUpperCase() + "/S" : "")
          }
          PanelActionButton {
            id: clearButton
            visible: root.hasFinished
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰎟"
            tooltipText: "Clear finished"
            foreground: root.fg
            fontFamily: root.bar.fontFamily
            onClicked: root.clearFinished()
          }
        }

        Flickable {
          visible: !root.showSettings && root.jobs.length > 0
          width: parent.width
          height: Math.min(jobsColumn.implicitHeight, Style.space(420))
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
                height: cardContent.implicitHeight + Style.space(20)
                radius: Style.cornerRadius
                color: root.tint(0.06)

                Column {
                  id: cardContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.space(10)
                  spacing: Style.space(8)

                  Row {
                    id: cardRow
                    width: parent.width
                    spacing: Style.space(12)

                    // Thumbnail with the quality badge (and a shrink icon for shrink jobs).
                    Rectangle {
                      id: cardThumb
                      width: Style.space(104)
                      height: Style.space(58)
                      radius: Style.cornerRadius
                      clip: true
                      color: root.tint(0.08)
                      anchors.verticalCenter: parent.verticalCenter

                      Image {
                        anchors.fill: parent
                        source: card.job.thumbnail
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 208
                        opacity: card.job.phase === "cancelled" || card.job.missing ? 0.4 : 1
                      }
                      Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: Style.space(4)
                        width: badge.implicitWidth + Style.space(8)
                        height: badge.implicitHeight + Style.space(2)
                        radius: Style.cornerRadius
                        color: Qt.rgba(0, 0, 0, 0.72)
                        Text {
                          id: badge
                          anchors.centerIn: parent
                          text: (card.job.kind === "shrink" ? "󰁯 " : "") + card.job.label
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
                          color: root.fg
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
                        color: root.tint(0.12)
                        Rectangle {
                          width: parent.width * Math.min(1, (card.job.phase === "done" ? 100 : card.job.shownPercent) / 100)
                          height: parent.height
                          radius: parent.radius
                          color: card.stateColor
                          visible: card.job.phase !== "cancelled"
                        }
                        Rectangle {
                          id: shimmer
                          visible: card.job.phase === "finishing" || card.job.phase === "running" && card.job.percent === 0
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

                      // Status: bytes · part on the left, speed · time left on the right
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
                                                     : [j.totalBytes > 0 ? root.humanBytes(j.totalBytes) : "",
                                                        j.subs && j.subs.length ? j.subs.length + (j.subs.length === 1 ? " subtitle" : " subtitles") : "",
                                                        "Saved"].filter(function(s) { return s }).join("  ·  ")
                            if (j.kind === "shrink") return j.label === "GIF" ? "Making the GIF…" : "Encoding to fit " + j.label + "…"
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
                          visible: card.job.phase === "running" && (card.job.totalBytes > 0 || card.job.kind === "shrink")
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
                        visible: card.job.kind === "download" && (card.job.phase === "running" || card.job.phase === "paused")
                        iconText: card.job.phase === "paused" ? "󰐊" : "󰏤"
                        tooltipText: card.job.phase === "paused" ? "Resume" : "Pause"
                        foreground: root.fg
                        fontFamily: root.bar.fontFamily
                        onClicked: card.job.phase === "paused" ? card.job.resume() : card.job.pause()
                      }
                      PanelActionButton {
                        visible: card.job.phase === "done" && !card.job.missing
                        iconText: "󰐊"
                        tooltipText: "Play"
                        foreground: root.fg
                        fontFamily: root.bar.fontFamily
                        onClicked: { Quickshell.execDetached(["xdg-open", card.job.file]); root.close() }
                      }
                      PanelActionButton {
                        visible: card.job.phase === "done" && !card.job.missing
                        iconText: "󰉋"
                        tooltipText: "Show in folder"
                        foreground: root.fg
                        fontFamily: root.bar.fontFamily
                        onClicked: { root.revealFile(card.job.file); root.close() }
                      }
                      PanelActionButton {
                        visible: card.job.kind === "download" && card.job.isVideoFile && !card.job.missing
                        iconText: "󰁯"
                        tooltipText: "Shrink for sharing / make a GIF"
                        foreground: card.job.shrinkOpen ? Color.accent : root.fg
                        fontFamily: root.bar.fontFamily
                        onClicked: card.job.shrinkOpen = !card.job.shrinkOpen
                      }
                      PanelActionButton {
                        visible: card.job.outdated > 0 && card.job.phase === "error"
                        iconText: "󰚰"
                        tooltipText: "yt-dlp is " + card.job.outdated + " days old: update"
                        foreground: root.warnColor
                        fontFamily: root.bar.fontFamily
                        onClicked: root.updateYtdlp()
                      }
                      PanelActionButton {
                        visible: card.job.phase === "error" || card.job.phase === "cancelled"
                        iconText: "󰑐"
                        tooltipText: "Retry"
                        foreground: root.fg
                        fontFamily: root.bar.fontFamily
                        onClicked: card.job.retry()
                      }
                      PanelActionButton {
                        iconText: card.job.finished ? "󰅖" : "󰜺"
                        tooltipText: card.job.finished ? "Remove from list" : "Cancel"
                        foreground: root.fg
                        fontFamily: root.bar.fontFamily
                        onClicked: card.job.finished ? root.removeJob(card.job) : card.job.cancel()
                      }
                    }
                  }

                  // Shrink targets for a finished video.
                  Column {
                    visible: card.job.shrinkOpen && card.job.isVideoFile && !card.job.missing
                    width: parent.width
                    spacing: Style.space(6)
                    SectionLabel { text: "MAKE A SMALLER COPY" }
                    Flow {
                      width: parent.width
                      spacing: Style.space(6)
                      Repeater {
                        model: [["10", "Discord", "10 MB"], ["16", "WhatsApp", "16 MB"], ["25", "Email", "25 MB"],
                                ["50", "50 MB", ""], ["gif", "GIF", "first 15 s"]]
                        Chip {
                          required property var modelData
                          width: (parent.width - Style.space(6) * 4) / 5
                          height: Style.space(42)
                          text: modelData[1]
                          sub: modelData[2]
                          onClicked: { card.job.shrinkOpen = false; root.startShrink(card.job, modelData[0]) }
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
