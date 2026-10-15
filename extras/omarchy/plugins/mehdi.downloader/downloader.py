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
#         progress <percent> <speed> <eta>
#         stage <text>            (merging, converting to mp3, ...)
#         done <file path>
#         error <message>
import json, os, re, subprocess, sys

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

def download(url, quality, outdir):
    os.makedirs(outdir, exist_ok=True)
    args = ["--newline", "--no-part", "-o", os.path.join(outdir, "%(title).150B [%(id)s].%(ext)s"),
            "--progress-template", "download:progress %(progress._percent_str)s %(progress._speed_str)s %(progress._eta_str)s",
            "--print", "after_move:done %(filepath)s"]
    if quality == "audio":
        args += ["-f", "ba/b", "-x", "--audio-format", "mp3", "--audio-quality", "0"]
    else:
        h = int(quality)
        args += ["-f", f"bv*[height<={h}]+ba/b[height<={h}]", "-S", f"res:{h},ext:mp4:m4a",
                 "--merge-output-format", "mp4"]
    p = subprocess.Popen(ytdlp(*args, url), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    last_err = ""
    for line in p.stdout:
        line = line.strip()
        if line.startswith(("progress ", "done ")):
            print(re.sub(r"\s+", " ", line), flush=True)
        elif line.startswith("[Merger]"):
            print("stage merging video + audio", flush=True)
        elif line.startswith("[ExtractAudio]"):
            print("stage converting to mp3", flush=True)
        elif line.startswith("ERROR:"):
            last_err = line[6:].strip()
    if p.wait() != 0:
        print("error " + (last_err or "download failed"), flush=True)

if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "info":
        info(sys.argv[2])
    elif len(sys.argv) >= 5 and sys.argv[1] == "download":
        download(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        sys.exit("usage: downloader.py info <url> | download <url> <height|audio> <dir>")
