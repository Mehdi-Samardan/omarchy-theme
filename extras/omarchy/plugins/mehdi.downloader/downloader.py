#!/usr/bin/env python3
# Helper for the mehdi.downloader bar widget, wrapping yt-dlp.
#
#   downloader.py info <url>
#       Prints one JSON line: title, uploader, duration, thumbnail, the video
#       heights on offer (each with its best fps, bitrate and an estimated
#       size), the best audio, and "extra": yt-dlp options the site needed
#       (browser cookies, browser impersonation). Or {"error": "..."}.
#       When a site refuses, it retries once with your browser's cookies and
#       a browser fingerprint, when those are available.
#
#   downloader.py download <url> <best|height|mp3|audio> <dir> [<work dir>] [<extra JSON>]
#       best = highest resolution and bitrate, <height> = the highest-bitrate
#       stream at that height, mp3 = 320 kbps MP3, audio = the original audio
#       track without re-encoding. <extra JSON> is the "extra" list from info.
#       Downloads to <dir> and prints progress lines the widget parses:
#         progress <percent> <done bytes> <total bytes> <speed B/s> <eta s> <part> <parts>
#         stage <text>            (merging, converting to mp3, ...)
#         done <file path>
#         error <message>
#       The percentage covers every stream yt-dlp fetches (YouTube sends video
#       and audio separately), measured in bytes, so it climbs once from 0 to
#       100 instead of restarting per stream. Speed is smoothed and the time
#       left is the remaining bytes over that speed.
#       Files are named "<title> [<id>] <height>p.mp4" (or .mp3), so several
#       resolutions of one video can download side by side. Work-in-progress
#       files live in a work folder (<work dir>, or a fresh temp folder) that is
#       removed when the download ends or is cancelled (SIGTERM), so a cancel
#       leaves nothing behind. Pause = create <work dir>/.paused, then SIGTERM:
#       the folder is kept and the same command later resumes from it.
#       Files get the title, channel, date and chapters embedded, plus the
#       thumbnail as cover art.
import json, os, re, shutil, signal, subprocess, sys, tempfile, time

def ytdlp(*args):
    return ["yt-dlp", "--no-playlist", "--no-warnings", *args]

# yt-dlp's errors, in plain words.
FRIENDLY = [
    (r"Private video", "This video is private"),
    (r"confirm your age|age.restricted|inappropriate for some users", "Age-restricted, sign-in required"),
    (r"not a bot", "The site wants a sign-in to confirm you're not a bot"),
    (r"members.only|Join this channel", "Members-only video"),
    (r"live event will begin|Premieres in", "This video hasn't started yet"),
    (r"Unsupported URL", "This site or link isn't supported"),
    (r"Requested format is not available", "That resolution isn't available anymore"),
    (r"HTTP Error 404|Not Found", "Nothing found at this link (404)"),
    (r"HTTP Error 403|Forbidden", "The site refused the download (403)"),
    (r"HTTP Error 429|Too Many Requests", "Too many requests, try again in a bit"),
    (r"Video unavailable|has been removed|no longer available", "Video unavailable"),
    (r"geo|not available in your country", "Not available in your country"),
    (r"Unable to download webpage|Name or service not known|timed out|Connection", "Couldn't reach the site, check your connection"),
    (r"No space left", "Not enough disk space"),
]

def friendly(msg):
    msg = re.sub(r"^ERROR:\s*", "", msg or "").strip()
    for pattern, text in FRIENDLY:
        if re.search(pattern, msg, re.I): return text
    return re.sub(r"^\[[^\]]+\]\s*[^:]*:\s*", "", msg) or "Download failed"

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
    p = subprocess.run(ytdlp("-J", *extra, url), capture_output=True, text=True)
    if p.returncode != 0:
        return None, (p.stderr.strip().splitlines() or ["yt-dlp failed"])[-1]
    try: return json.loads(p.stdout), None
    except ValueError: return None, "yt-dlp returned no data"

def info(url):
    extra = []
    d, err = probe(url, extra)
    if d is None and re.search(RETRYABLE, err, re.I):
        extra = browser_extras()
        if extra: d, err = probe(url, extra)
    if d is None:
        hint = ""
        if re.search(RETRYABLE, err, re.I) and not browser_extras():
            hint = " (install python-secretstorage and python-curl_cffi to let it use your browser login)"
        print(json.dumps({"error": friendly(err) + hint})); return

    duration = d.get("duration") or 0
    fmts = d.get("formats") or [d]
    size = lambda f: f.get("filesize") or f.get("filesize_approx") or (
        (f.get("tbr") or 0) * 125 * duration if duration else 0)
    is_audio = lambda f: f.get("vcodec") == "none" and f.get("acodec") not in (None, "none")
    # vcodec None means "not reported": many sites (X, Instagram, ...) don't say,
    # so anything that isn't known to be audio-only counts as video.
    is_video = lambda f: f.get("vcodec") != "none" and not (f.get("vcodec") is None and f.get("acodec") not in (None, "none") and not f.get("height"))

    audios = [f for f in fmts if is_audio(f)]
    best_audio = max(audios, key=lambda f: (f.get("abr") or f.get("tbr") or 0, size(f)), default=None)
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
        "thumbnail": d.get("thumbnail") or "",
        "hasVideo": bool(heights),
        "heights": known,
        "best": known[0] if known else heights.get(0),
        "audio": {"codec": (best_audio or {}).get("acodec", "").split(".")[0], "kbps": round((best_audio or {}).get("abr") or 0),
                  "size": audio_size} if best_audio or not heights else None,
        "extra": extra,
    }))

def num(v):
    try: return float(v)
    except (TypeError, ValueError): return None

def download(url, quality, outdir, workdir=None, extra=None):
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
    # Highest bitrate first: at a given height prefer more fps, then more bits.
    if quality == "mp3":
        args += ["-f", "ba/b", "-S", "abr,asr", "-x", "--audio-format", "mp3", "--audio-quality", "320K"]
    elif quality == "audio":
        args += ["-f", "ba/b", "-S", "abr,asr", "-x"]          # original codec, no re-encode
    elif quality == "best":
        args += ["-f", "bv*+ba/b", "-S", "res,fps,vbr,abr,asr", "--merge-output-format", "mp4"]
    else:
        h = int(quality)
        args += ["-f", f"bv*[height<={h}]+ba/b[height<={h}]/b", "-S", f"res:{h},fps,vbr,abr,asr",
                 "--merge-output-format", "mp4"]
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

    def emit(force=False):
        nonlocal last_emit
        now = time.monotonic()
        if not force and now - last_emit < 0.25: return
        last_emit = now
        total = sum(p["total"] for p in parts.values())
        done = sum(min(p["done"], p["total"]) if p["total"] else p["done"] for p in parts.values())
        pct = min(99.9, done * 100 / total) if total else 0
        eta = (total - done) / speed if speed and total > done else 0
        active = next((i for i, f in enumerate(order) if parts[f]["done"] < parts[f]["total"]), len(order) - 1)
        print(f"progress {pct:.1f} {int(done)} {int(total)} {int(speed or 0)} {int(eta)} {active + 1} {len(order)}", flush=True)

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
                values += [None] * (5 - len(values))
            if len(values) < 5: values += [None] * (5 - len(values))
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
            emit(force=True)
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
            emit()
            # yt-dlp stays quiet about post-processing, so announce it once every
            # stream is in: merging two streams or converting audio takes a moment.
            if not finishing and order and all(parts[x]["total"] and parts[x]["done"] >= parts[x]["total"] for x in order):
                finishing = True
                emit(force=True)
                if quality == "mp3": print("stage converting to mp3", flush=True)
                elif quality == "audio": print("stage extracting the audio", flush=True)
                elif len(order) > 1: print("stage merging video and audio", flush=True)
                else: print("stage finishing the file", flush=True)
        elif line.startswith("done "):
            for part in parts.values(): part["done"] = part["total"] = max(part["done"], part["total"])
            print(re.sub(r"\s+", " ", line), flush=True)
        elif line.startswith("[Merger]"):
            print("stage merging video and audio", flush=True)
        elif line.startswith("[ExtractAudio]"):
            print("stage converting to mp3", flush=True)
        elif line.startswith(("[FixupM3u8]", "[FixupM4a]", "[VideoConvertor]", "[VideoRemuxer]")):
            print("stage finishing the file", flush=True)
        elif line.startswith("[EmbedThumbnail]") or line.startswith("[Metadata]"):
            print("stage adding cover and details", flush=True)
        elif line.startswith("ERROR:"):
            last_err = line[6:].strip()
    code = p.wait()
    shutil.rmtree(tmp, ignore_errors=True)
    if code != 0:
        print("error " + friendly(last_err), flush=True)

if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "info":
        info(sys.argv[2])
    elif len(sys.argv) >= 5 and sys.argv[1] == "download":
        download(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5] if len(sys.argv) > 5 and sys.argv[5] else None,
                 json.loads(sys.argv[6]) if len(sys.argv) > 6 and sys.argv[6] else None)
    else:
        sys.exit("usage: downloader.py info <url> | download <url> <best|height|mp3|audio> <dir> [<work dir>] [<extra JSON>]")
