#!/usr/bin/env python3
"""transcribe.py — turn a (stereo) recording into a timestamped, speaker-labeled
Markdown transcript using mlx-whisper.

Channel convention (set by the recorder):
  left channel  -> --label-left  (default "Me",   your microphone)
  right channel -> --label-right (default "Them", system audio / remote side)

Each channel is transcribed independently, then segments from both are merged in
chronological order. For a mono file, a single pass labeled --label-left is run.

Writes <stem>.transcript.md into --out-dir and prints ONLY that path on stdout;
all progress goes to stderr.
"""
import argparse
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def log(msg):  # progress -> stderr
    print(msg, file=sys.stderr, flush=True)


def run(cmd):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def channel_count(path):
    try:
        out = run([
            "ffprobe", "-v", "error", "-select_streams", "a:0",
            "-show_entries", "stream=channels", "-of", "json", str(path),
        ]).stdout
        return int(json.loads(out)["streams"][0]["channels"])
    except Exception:
        return 1


def extract_channel(src, idx, dst):
    """Pull a single channel (0=left, 1=right) as 16 kHz mono — no downmix."""
    run([
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-i", str(src), "-af", f"pan=mono|c0=c{idx}",
        "-ar", "16000", "-ac", "1", str(dst),
    ])


def collapse_repeats(text, max_run=3):
    """Drop runs of the same word (a common Whisper hallucination on silence)."""
    out, run_len = [], 0
    for w in text.split():
        if out and w.lower() == out[-1].lower():
            run_len += 1
            if run_len >= max_run:
                continue
        else:
            run_len = 0
        out.append(w)
    return " ".join(out)


def hms(seconds):
    seconds = int(round(seconds))
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    return f"{h:02d}:{m:02d}:{s:02d}"


def transcribe_channel(wav, model, lang, label):
    import mlx_whisper

    res = mlx_whisper.transcribe(
        str(wav), path_or_hf_repo=model, language=lang,
        condition_on_previous_text=False, verbose=False,
    )
    segs = []
    for s in res.get("segments", []):
        txt = collapse_repeats((s.get("text") or "").strip())
        if txt:
            segs.append((float(s["start"]), label, txt))
    return segs


def main():
    p = argparse.ArgumentParser()
    p.add_argument("audio")
    p.add_argument("--out-dir", required=True)
    p.add_argument("--model", required=True)
    p.add_argument("--lang", default="en")
    p.add_argument("--label-left", default="Me")
    p.add_argument("--label-right", default="Them")
    args = p.parse_args()

    audio = Path(args.audio).expanduser()
    if not audio.exists():
        log(f"Audio not found: {audio}")
        sys.exit(1)

    ch = channel_count(audio)
    log(f"Audio has {ch} channel(s).")

    segments = []
    t0 = time.perf_counter()
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        if ch >= 2:
            left, right = td / "left.wav", td / "right.wav"
            extract_channel(audio, 0, left)
            extract_channel(audio, 1, right)
            log(f"Transcribing left channel ({args.label_left})…")
            segments += transcribe_channel(left, args.model, args.lang, args.label_left)
            log(f"Transcribing right channel ({args.label_right})…")
            segments += transcribe_channel(right, args.model, args.lang, args.label_right)
        else:
            mono = td / "mono.wav"
            extract_channel(audio, 0, mono)
            log("Transcribing single channel…")
            segments += transcribe_channel(mono, args.model, args.lang, args.label_left)
    dt = time.perf_counter() - t0

    segments.sort(key=lambda x: x[0])

    out_dir = Path(args.out_dir).expanduser()
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{audio.stem}.transcript.md"

    lines = [
        f"# Transcript — {audio.stem}", "",
        f"*Transcribed locally with {args.model} in {hms(dt)}*", "",
    ]
    if not segments:
        lines.append("_(No speech detected.)_")
    else:
        for start, label, txt in segments:
            lines.append(f"[{hms(start)}] **{label}:** {txt}")
            lines.append("")
    out_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")

    log(f"Done in {hms(dt)} — {len(segments)} segment(s)")
    print(str(out_path))  # the ONLY thing on stdout


if __name__ == "__main__":
    main()
