#!/usr/bin/env python3
# Helper for the mehdi.downloader bar widget, wrapping yt-dlp and ffmpeg.
#
#   downloader.py info <url> [<dir>]
#       Prints one JSON line. For a single video: title, uploader, duration,
#       thumbnail, the heights on offer (best fps, bitrate and an estimated
#       size for each), the best audio, the free space in <dir>, and "extra":
#       yt-dlp options the site needed (browser
#       cookies, browser impersonation). For a playlist or channel:
#       {"playlist": true, title, uploader, count, entries: [{url, title, ...}]}.
#       On failure {"error": "...", "outdated": <days>} (outdated only when an
#       old yt-dlp is the likely cause). A site that refuses is retried once
#       with your browser's cookies and fingerprint, when those are available.
#
#   downloader.py download <url> <best|height|mp3|audio> <dir> [<work dir>] [<extra JSON>] [<options JSON>]
#       best = highest resolution and bitrate, <height> = the highest-bitrate
#       stream at that height, mp3 = 320 kbps MP3, audio = the original audio
#       track without re-encoding. <extra JSON> is the "extra" list from info.
#       <options JSON>: {"rate": "5M"} caps the speed.
#
#       Audio is always the original-language track: YouTube adds auto-dubbed
#       tracks, and those often report a higher bitrate, so "highest bitrate"
#       alone would pick a dub.
#
#   downloader.py shrink <file> <megabytes|gif>
#       Re-encodes a finished download to fit a size (Discord, WhatsApp, ...)
#       as "<name> (<n> MB).mp4", or makes "<name>.gif" from its first 15 s.
#
#   Download and shrink print lines the widget parses:
#     progress <percent> <done bytes> <total bytes> <speed B/s> <eta s> <part> <parts>
#     stage <text>            (merging, converting, encoding, ...)
#     done <file path>
#     outdated <days>         (before an error that an old yt-dlp likely caused)
#     error <message>
#
#   Download progress covers every stream yt-dlp fetches (YouTube sends video
#   and audio separately), measured in bytes, so it climbs once from 0 to 100.
#   Files are named "<title> [<id>] <height>p.mp4" (or .mp3/.m4a/...), so
#   several qualities of one video can download side by side. Work files live
#   in <work dir> (or a fresh temp folder), removed when the download ends or
#   is cancelled (SIGTERM). Pause = create <work dir>/.paused, then SIGTERM: the
#   folder is kept and the same command later resumes from it. Files get the
#   title, channel, date and chapters embedded, plus the thumbnail as cover art.
import datetime, json, os, re, shutil, signal, subprocess, sys, tempfile, time

def ytdlp(*args):
    return ["yt-dlp", "--no-playlist", "--no-warnings", *args]

def num(v):
    try: return float(v)
    except (TypeError, ValueError): return None

def emit(*fields):
    print(" ".join(str(f) for f in fields), flush=True)

# ---------- Errors ----------

# yt-dlp's errors, in plain words.
FRIENDLY = [
    (r"Private video", "This video is private"),
    (r"confirm your age|age.restricted|inappropriate for some users", "Age-restricted, sign-in required"),
    (r"not a bot", "The site wants a sign-in to confirm you're not a bot"),
    (r"members.only|Join this channel", "Members-only video"),
    (r"live event will begin|Premieres in", "This video hasn't started yet"),
    (r"Unsupported URL", "This site or link isn't supported"),
    (r"Requested format is not available", "That quality isn't available anymore"),
    (r"HTTP Error 404|Not Found", "Nothing found at this link (404)"),
    (r"HTTP Error 403|Forbidden", "The site refused the download (403)"),
    (r"HTTP Error 429|Too Many Requests", "Too many requests, try again in a bit"),
    (r"Video unavailable|is unavailable|has been removed|no longer available", "Video unavailable"),
    (r"geo|not available in your country", "Not available in your country"),
    (r"Unable to download webpage|Name or service not known|timed out|Connection", "Couldn't reach the site, check your connection"),
    (r"No space left", "Not enough disk space"),
]

def friendly(msg):
    msg = re.sub(r"^ERROR:\s*", "", msg or "").strip()
    for pattern, text in FRIENDLY:
        if re.search(pattern, msg, re.I): return text
    return re.sub(r"^\[[^\]]+\]\s*[^:]*:\s*", "", msg) or "Download failed"

# Errors that a newer yt-dlp typically fixes (sites change, yt-dlp follows).
EXTRACTOR_BREAKAGE = r"Unable to extract|nsig|signature|Requested format is not available|HTTP Error 403|not a bot|Unsupported URL|KeyError|NoneType|unable to download video data"

def ytdlp_age_days():
    try:
        v = subprocess.run(["yt-dlp", "--version"], capture_output=True, text=True).stdout.strip()
        y, m, d = (int(x) for x in v.split(".")[:3])
        return (datetime.date.today() - datetime.date(y, m, d)).days
    except Exception:
        return 0

def outdated_days(err):
    """Days since this yt-dlp was released, when it's old and the error smells like it."""
    age = ytdlp_age_days()
    return age if age >= 30 and re.search(EXTRACTOR_BREAKAGE, err or "", re.I) else 0

# ---------- Info ----------

def browser_extras():
    """yt-dlp options that make requests look like your browser, if available."""
    extras = []
    try:
        import secretstorage  # noqa: F401  (needed to decrypt Chrome cookies)
        for browser, path in (("chrome", "~/.config/google-chrome"), ("chromium", "~/.config/chromium"),
                              ("brave", "~/.config/BraveSoftware"), ("firefox", "~/.mozilla/firefox")):
            if os.path.isdir(os.path.expanduser(path)):
                extras += ["--cookies-from-browser", browser]
                break
    except ImportError:
        if os.path.isdir(os.path.expanduser("~/.mozilla/firefox")):   # Firefox needs no keyring
            extras += ["--cookies-from-browser", "firefox"]
    try:
        import curl_cffi  # noqa: F401
        extras += ["--impersonate", "chrome"]
    except ImportError:
        pass
    return extras

RETRYABLE = r"sign.?in|log.?in|not a bot|confirm your age|HTTP Error 40[13]|Forbidden|cloudflare|Unsupported URL|Unable to extract|private"

def probe(url, extra):
    # --flat-playlist keeps playlists and channels fast (entries, not full info).
    p = subprocess.run(ytdlp("-J", "--flat-playlist", *extra, url), capture_output=True, text=True)
    if p.returncode != 0:
        return None, (p.stderr.strip().splitlines() or ["yt-dlp failed"])[-1]
    try: return json.loads(p.stdout), None
    except ValueError: return None, "yt-dlp returned no data"

def free_bytes(path):
    path = os.path.abspath(path or os.path.expanduser("~"))
    while not os.path.isdir(path) and path != "/": path = os.path.dirname(path)
    st = os.statvfs(path)
    return st.f_bavail * st.f_frsize

def thumb_of(d):
    if d.get("thumbnail"): return d["thumbnail"]
    thumbs = [t for t in d.get("thumbnails") or [] if t.get("url")]
    return max(thumbs, key=lambda t: (t.get("width") or 0) * (t.get("height") or 0))["url"] if thumbs else ""

def playlist_info(d, extra, outdir):
    entries = []
    for e in (d.get("entries") or [])[:300]:
        if not e: continue
        u = e.get("url") or e.get("webpage_url")
        if not u: continue
        if not re.match(r"https?://", u) and e.get("ie_key") == "Youtube":
            u = "https://www.youtube.com/watch?v=" + u
        entries.append({"url": u, "title": e.get("title") or u, "duration": e.get("duration") or 0,
                        "uploader": e.get("uploader") or e.get("channel") or "", "thumbnail": thumb_of(e)})
    return {"playlist": True, "title": d.get("title") or "Playlist",
            "uploader": d.get("uploader") or d.get("channel") or "", "count": len(entries),
            "thumbnail": thumb_of(d) or (entries[0]["thumbnail"] if entries else ""),
            "entries": entries, "extra": extra, "freeBytes": free_bytes(outdir)}

def info(url, outdir=None):
    extra = []
    d, err = probe(url, extra)
    if d is None and re.search(RETRYABLE, err, re.I):
        extra = browser_extras()
        if extra: d, err = probe(url, extra)
    if d is None:
        hint = ""
        if re.search(RETRYABLE, err, re.I) and not browser_extras():
            hint = " (install python-secretstorage and python-curl_cffi to let it use your browser login)"
        print(json.dumps({"error": friendly(err) + hint, "outdated": outdated_days(err)})); return

    if d.get("_type") in ("playlist", "multi_video") and d.get("entries") is not None:
        print(json.dumps(playlist_info(d, extra, outdir))); return

    duration = d.get("duration") or 0
    fmts = d.get("formats") or [d]
    size = lambda f: f.get("filesize") or f.get("filesize_approx") or (
        (f.get("tbr") or 0) * 125 * duration if duration else 0)
    is_audio = lambda f: f.get("vcodec") == "none" and f.get("acodec") not in (None, "none")
    # vcodec None means "not reported": many sites (X, Instagram, ...) don't say,
    # so anything that isn't known to be audio-only counts as video.
    is_video = lambda f: f.get("vcodec") != "none" and not (f.get("vcodec") is None and f.get("acodec") not in (None, "none") and not f.get("height"))

    audios = [f for f in fmts if is_audio(f)]
    original = lambda f: (f.get("language_preference") or 0) >= 10 or "original" in (f.get("format_note") or "")
    best_audio = max(audios, key=lambda f: (original(f), f.get("abr") or f.get("tbr") or 0, size(f)), default=None)

    audio_size = size(best_audio) if best_audio else 0

    heights = {}
    for f in fmts:
        if not is_video(f): continue
        h = f.get("height") or 0
        rate = f.get("vbr") or f.get("tbr") or 0
        cur = heights.get(h)
        if cur is None or (f.get("fps") or 0, rate) > (cur["fps"], cur["kbps"]):
            heights[h] = {"height": h, "fps": round(f.get("fps") or 0), "kbps": round(rate),
                          "size": size(f) + (audio_size if f.get("acodec") in (None, "none") and best_audio else 0)}
    known = [heights[h] for h in sorted(heights, reverse=True) if h]

    print(json.dumps({
        "title": d.get("title") or url,
        "uploader": d.get("uploader") or d.get("channel") or d.get("extractor_key") or "",
        "duration": duration,
        "thumbnail": thumb_of(d),
        "hasVideo": bool(heights),
        "heights": known,
        "best": known[0] if known else heights.get(0),
        "audio": {"codec": (best_audio or {}).get("acodec", "").split(".")[0], "kbps": round((best_audio or {}).get("abr") or 0),
                  "size": audio_size} if best_audio or not heights else None,
        "freeBytes": free_bytes(outdir),
        "extra": extra,
    }))

# ---------- Download ----------

def download(url, quality, outdir, workdir=None, extra=None, options=None):
    options = options or {}
    outdir = os.path.abspath(outdir)
    os.makedirs(outdir, exist_ok=True)
    if workdir:
        tmp = os.path.abspath(workdir)
        os.makedirs(tmp, exist_ok=True)
        try: os.remove(os.path.join(tmp, ".paused"))   # resuming
        except FileNotFoundError: pass
    else:
        tmp = tempfile.mkdtemp(prefix=".downloading-", dir=outdir)
    suffix = {"best": " best", "mp3": "", "audio": ""}.get(quality, f" {quality}p")
    # --print would make yt-dlp quiet, so --progress keeps the progress lines.
    args = ["--newline", "--progress", "-P", outdir, "-P", f"temp:{tmp}",
            "--embed-metadata", "--embed-chapters",
            "-o", f"%(title).150B [%(id)s]{suffix}.%(ext)s",
            "--print", "before_dl:parts %(requested_formats.:.format_id)j %(requested_formats.:.filesize)j "
                       "%(requested_formats.:.filesize_approx)j %(format_id)j %(filesize,filesize_approx)j",
            "--progress-template", "download:progress %(info.format_id)s %(progress.downloaded_bytes)s "
                                   "%(progress.total_bytes)s %(progress.total_bytes_estimate)s %(progress.speed)s "
                                   "%(progress.fragment_index)s %(progress.fragment_count)s",
            "--print", "after_move:done %(filepath)s"]
    # Parallel fragments speed up HLS sites (X, Instagram, ...); YouTube answers them with 403.
    if not re.search(r"(youtube\.com|youtu\.be)/", url):
        args += ["--concurrent-fragments", "4"]
    # "lang" first keeps the original-language audio over auto-dubbed tracks;
    # after that the highest bitrate wins (more fps, then more bits per height).
    if quality == "mp3":
        args += ["-f", "ba/b", "-S", "lang,abr,asr", "-x", "--audio-format", "mp3", "--audio-quality", "320K"]
    elif quality == "audio":
        args += ["-f", "ba/b", "-S", "lang,abr,asr", "-x"]          # original codec, no re-encode
    elif quality == "best":
        args += ["-f", "bv*+ba/b", "-S", "lang,res,fps,vbr,abr,asr", "--merge-output-format", "mp4"]
    else:
        h = int(quality)
        args += ["-f", f"bv*[height<={h}]+ba/b[height<={h}]/b", "-S", f"lang,res:{h},fps,vbr,abr,asr",
                 "--merge-output-format", "mp4"]
    if options.get("rate") and re.fullmatch(r"\d+(\.\d+)?[KMG]?", str(options["rate"])):
        args += ["--limit-rate", str(options["rate"])]
    # Cover art: ffmpeg handles mp4/mp3/m4a; Opus/Ogg/WebM need mutagen.
    try:
        import mutagen  # noqa: F401
        args += ["--embed-thumbnail"]
    except ImportError:
        if quality != "audio": args += ["--embed-thumbnail"]
    args += extra or []

    parts = {}          # format_id -> {"done": bytes, "total": bytes}
    order = []          # format ids in download order
    speed = None        # smoothed bytes/s
    last_emit = 0.0
    finishing = False   # every stream downloaded, post-processing running

    def report(force=False):
        nonlocal last_emit
        now = time.monotonic()
        if not force and now - last_emit < 0.25: return
        last_emit = now
        total = sum(p["total"] for p in parts.values())
        done = sum(min(p["done"], p["total"]) if p["total"] else p["done"] for p in parts.values())
        pct = min(99.9, done * 100 / total) if total else 0
        eta = (total - done) / speed if speed and total > done else 0
        active = next((i for i, f in enumerate(order) if parts[f]["done"] < parts[f]["total"]), len(order) - 1)
        emit("progress", f"{pct:.1f}", int(done), int(total), int(speed or 0), int(eta), active + 1, len(order))

    p = subprocess.Popen(ytdlp(*args, url), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)

    def stop(*_):
        p.terminate()
        try: p.wait(5)
        except subprocess.TimeoutExpired: p.kill()
        if not os.path.exists(os.path.join(tmp, ".paused")):
            shutil.rmtree(tmp, ignore_errors=True)
        sys.exit(130)
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    last_err = ""
    for line in p.stdout:
        line = line.strip()
        if line.startswith("parts "):
            # Five JSON values separated by spaces; the lists contain spaces too.
            values, rest, dec = [], line[6:].strip(), json.JSONDecoder()
            try:
                while rest and len(values) < 5:
                    v, end = dec.raw_decode(rest)
                    values.append(v)
                    rest = rest[end:].lstrip()
            except ValueError:
                pass
            values += [None] * (5 - len(values))
            ids, sizes, approx, single_id, single_size = values
            if isinstance(ids, list) and ids:
                # yt-dlp drops unknown sizes from these lists, so only trust them
                # when they line up with the ids; progress fills in the rest.
                at = lambda xs, i: xs[i] if isinstance(xs, list) and len(xs) == len(ids) else 0
                for i, f in enumerate(ids):
                    order.append(str(f))
                    parts[str(f)] = {"done": 0, "total": num(at(sizes, i)) or num(at(approx, i)) or 0}
            elif single_id not in (None, "NA"):
                order.append(str(single_id))
                parts[str(single_id)] = {"done": 0, "total": num(single_size) or 0}
            report(force=True)
        elif line.startswith("progress "):
            f, got, tot, est, spd, frag_i, frag_n = (line.split(" ") + ["NA"] * 8)[1:8]
            if f not in parts:
                order.append(f)
                parts[f] = {"done": 0, "total": 0}
            part = parts[f]
            got, tot, est = num(got), num(tot), num(est)
            if tot or est: part["total"] = tot or est
            if got is not None:
                part["done"] = got
            elif num(frag_i) and num(frag_n) and part["total"]:
                part["done"] = part["total"] * num(frag_i) / num(frag_n)
            s_ = num(spd)
            if s_: speed = s_ if speed is None else speed * 0.8 + s_ * 0.2
            report()
            # yt-dlp stays quiet about post-processing, so announce it once every
            # stream is in: merging two streams or converting audio takes a moment.
            if not finishing and order and all(parts[x]["total"] and parts[x]["done"] >= parts[x]["total"] for x in order):
                finishing = True
                report(force=True)
                if quality == "mp3": emit("stage converting to mp3")
                elif quality == "audio": emit("stage extracting the audio")
                elif len(order) > 1: emit("stage merging video and audio")
                else: emit("stage finishing the file")
        elif line.startswith("done "):
            emit(re.sub(r"\s+", " ", line))
        elif line.startswith("ERROR:"):
            last_err = line[6:].strip()
    code = p.wait()
    shutil.rmtree(tmp, ignore_errors=True)
    if code != 0:
        days = outdated_days(last_err)
        if days: emit("outdated", days)
        emit("error", friendly(last_err))

# ---------- Shrink / GIF ----------

def probe_duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         capture_output=True, text=True).stdout.strip()
    return num(out) or 0

def has_encoder(name):
    out = subprocess.run(["ffmpeg", "-hide_banner", "-encoders"], capture_output=True, text=True).stdout
    return f" {name} " in out

def run_ffmpeg(cmd, seconds, label):
    """Run ffmpeg with -progress on stdout and turn it into progress lines."""
    p = subprocess.Popen(cmd + ["-progress", "pipe:1", "-nostats", "-loglevel", "error"],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)

    def stop(*_):
        p.terminate()
        try: p.wait(5)
        except subprocess.TimeoutExpired: p.kill()
        try: os.remove(cmd[-1])
        except OSError: pass
        sys.exit(130)
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    start, last = time.monotonic(), 0.0
    for line in p.stdout:
        if line.startswith("out_time_us="):
            t = (num(line.split("=", 1)[1]) or 0) / 1e6
            pct = min(99.9, t * 100 / seconds) if seconds else 0
            now = time.monotonic()
            if now - last >= 0.25:
                last = now
                elapsed = now - start
                eta = elapsed * (100 - pct) / pct if pct > 0 else 0
                emit("progress", f"{pct:.1f}", 0, 0, 0, int(eta), 0, 0)
    err = p.stderr.read().strip()
    return p.wait(), err

def shrink(path, target):
    if not os.path.isfile(path):
        emit("error", "The file isn't there anymore"); return
    duration = probe_duration(path)
    base = os.path.splitext(path)[0]
    emit("stage", "encoding")

    if target == "gif":
        seconds = min(15, duration or 15)
        out = base + ".gif"
        vf = ("fps=12,scale=480:-2:flags=lanczos,split[a][b];"
              "[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4")
        code, err = run_ffmpeg(["ffmpeg", "-y", "-t", str(seconds), "-i", path, "-vf", vf, "-loop", "0", out],
                               seconds, "gif")
        if code != 0: emit("error", "GIF failed: " + (err.splitlines() or ["ffmpeg error"])[-1]); return
        emit("done", out); return

    mb = float(target)
    if not duration:
        emit("error", "Can't read the video length"); return
    budget = mb * 1000 * 1000 * 8 * 0.94          # bits, with headroom for the container
    audio = 96_000 if budget / duration > 600_000 else 64_000
    out = f"{base} ({mb:g} MB).mp4"
    factor = 1.0
    for attempt in range(2):
        vbit = int((budget / duration - audio) * factor)
        if vbit < 120_000:
            need = (120_000 + audio) * duration / 8 / 1e6 / 0.94
            emit("error", f"Too long to fit in {mb:g} MB (needs about {need:.0f} MB)"); return
        height = 1080 if vbit > 4_500_000 else 720 if vbit > 1_800_000 else 480 if vbit > 800_000 else 360
        vf = f"scale=-2:'min({height},ih)'"
        if has_encoder("h264_nvenc"):
            venc = ["-c:v", "h264_nvenc", "-preset", "p5", "-rc", "cbr", "-b:v", str(vbit),
                    "-maxrate", str(vbit), "-bufsize", str(vbit * 2)]
        else:
            venc = ["-c:v", "libx264", "-preset", "medium", "-b:v", str(vbit),
                    "-maxrate", str(int(vbit * 1.3)), "-bufsize", str(vbit * 2)]
        cmd = ["ffmpeg", "-y", "-i", path, "-vf", vf, *venc, "-c:a", "aac", "-b:a", str(audio),
               "-movflags", "+faststart", out]
        code, err = run_ffmpeg(cmd, duration, "shrink")
        if code != 0:
            emit("error", "Shrinking failed: " + (err.splitlines() or ["ffmpeg error"])[-1]); return
        if os.path.getsize(out) <= mb * 1000 * 1000: break
        factor *= 0.85                             # came out too big: one more, tighter pass
    emit("done", out)

if __name__ == "__main__":
    a = sys.argv
    if len(a) >= 3 and a[1] == "info":
        info(a[2], a[3] if len(a) > 3 else None)
    elif len(a) >= 5 and a[1] == "download":
        download(a[2], a[3], a[4], a[5] if len(a) > 5 and a[5] else None,
                 json.loads(a[6]) if len(a) > 6 and a[6] else None,
                 json.loads(a[7]) if len(a) > 7 and a[7] else None)
    elif len(a) >= 4 and a[1] == "shrink":
        shrink(a[2], a[3])
    else:
        sys.exit("usage: downloader.py info <url> [<dir>] | download <url> <best|height|mp3|audio> <dir> "
                 "[<work dir>] [<extra JSON>] [<options JSON>] | shrink <file> <megabytes|gif>")
