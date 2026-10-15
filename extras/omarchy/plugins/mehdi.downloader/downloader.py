#!/usr/bin/env python3
# Helper for the mehdi.downloader bar widget, wrapping yt-dlp.
#
#   downloader.py info <url>
#       Prints one JSON line: title, uploader, duration, thumbnail and the
#       available video heights with an estimated size (best video at that
#       height + best audio), or {"error": "..."}.
#
#   downloader.py download <url> <height|audio> <dir>
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
#       files live in a private temp folder that is removed when the download
#       ends or is cancelled (SIGTERM), so a cancel leaves nothing behind.
import json, os, re, shutil, signal, subprocess, sys, tempfile, time

def ytdlp(*args):
    return ["yt-dlp", "--no-playlist", "--no-warnings", *args]

def info(url):
    p = subprocess.run(ytdlp("-J", url), capture_output=True, text=True)
    if p.returncode != 0:
        msg = (p.stderr.strip().splitlines() or ["yt-dlp failed"])[-1]
        print(json.dumps({"error": re.sub(r"^ERROR:\s*", "", msg)})); return
    d = json.loads(p.stdout)
    fmts = d.get("formats") or []
    size = lambda f: f.get("filesize") or f.get("filesize_approx") or 0
    audio = max((size(f) for f in fmts if f.get("vcodec") == "none" and f.get("acodec") not in (None, "none")), default=0)
    heights = {}
    for f in fmts:
        h = f.get("height")
        if not h or f.get("vcodec") in (None, "none"): continue
        s = size(f) + (audio if f.get("acodec") in (None, "none") else 0)
        heights[h] = max(heights.get(h, 0), s)
    print(json.dumps({
        "title": d.get("title") or url,
        "uploader": d.get("uploader") or d.get("channel") or d.get("extractor_key") or "",
        "duration": d.get("duration") or 0,
        "thumbnail": d.get("thumbnail") or "",
        "heights": [{"height": h, "size": heights[h]} for h in sorted(heights, reverse=True)],
        "audioSize": audio,
    }))

def num(v):
    try: return float(v)
    except (TypeError, ValueError): return None

def download(url, quality, outdir):
    os.makedirs(outdir, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix=".downloading-", dir=outdir)
    suffix = "" if quality == "audio" else f" {int(quality)}p"
    # --print would make yt-dlp quiet, so --progress keeps the progress lines.
    args = ["--newline", "--progress", "-P", outdir, "-P", f"temp:{tmp}",
            "-o", f"%(title).150B [%(id)s]{suffix}.%(ext)s",
            "--print", "before_dl:parts %(requested_formats.:.format_id)j %(requested_formats.:.filesize)j "
                       "%(requested_formats.:.filesize_approx)j %(format_id)j %(filesize,filesize_approx)j",
            "--progress-template", "download:progress %(info.format_id)s %(progress.downloaded_bytes)s "
                                   "%(progress.total_bytes)s %(progress.total_bytes_estimate)s %(progress.speed)s "
                                   "%(progress.fragment_index)s %(progress.fragment_count)s",
            "--print", "after_move:done %(filepath)s"]
    if quality == "audio":
        args += ["-f", "ba/b", "-x", "--audio-format", "mp3", "--audio-quality", "0"]
    else:
        h = int(quality)
        args += ["-f", f"bv*[height<={h}]+ba/b[height<={h}]", "-S", f"res:{h},ext:mp4:m4a",
                 "--merge-output-format", "mp4"]

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
                for i, f in enumerate(ids):
                    order.append(str(f))
                    parts[str(f)] = {"done": 0, "total": (sizes[i] if isinstance(sizes, list) else 0)
                                     or (approx[i] if isinstance(approx, list) else 0) or 0}
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
                if quality == "audio": print("stage converting to mp3", flush=True)
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
        elif line.startswith("ERROR:"):
            last_err = line[6:].strip()
    code = p.wait()
    shutil.rmtree(tmp, ignore_errors=True)
    if code != 0:
        print("error " + (last_err or "download failed"), flush=True)

if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "info":
        info(sys.argv[2])
    elif len(sys.argv) >= 5 and sys.argv[1] == "download":
        download(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        sys.exit("usage: downloader.py info <url> | download <url> <height|audio> <dir>")
