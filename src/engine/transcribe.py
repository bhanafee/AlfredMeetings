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


def load_pcm(wav):
    """Load a 16-bit mono WAV as (samples float32 in [-1,1], sample_rate)."""
    import wave
    import numpy as np

    with wave.open(str(wav)) as w:
        sr = w.getframerate()
        raw = w.readframes(w.getnframes())
    return np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0, sr


def transcribe_channel(wav, model, lang, no_speech_threshold=0.6, silence_dbfs=-50.0):
    """Transcribe one mono channel -> list of (start, end, text), silence-gated."""
    import mlx_whisper
    import numpy as np

    res = mlx_whisper.transcribe(
        str(wav), path_or_hf_repo=model, language=lang,
        condition_on_previous_text=False, verbose=False,
    )
    samples, sr = load_pcm(wav)
    segs = []
    for s in res.get("segments", []):
        # On a silent channel (e.g. while only the other side talks) Whisper
        # hallucinates filler like "Thank you." — often with a *low* no_speech_prob,
        # so the reliable tell is the audio itself being silent. Drop a segment if
        # its actual RMS energy is below the silence floor, with no_speech_prob as a
        # secondary guard for genuinely-uncertain output.
        if float(s.get("no_speech_prob", 0.0)) >= no_speech_threshold:
            continue
        st, en = float(s["start"]), float(s["end"])
        window = samples[int(st * sr): int(en * sr)]
        if len(window):
            dbfs = 20.0 * np.log10(float(np.sqrt((window ** 2).mean())) + 1e-12)
            if dbfs < silence_dbfs:
                continue
        txt = collapse_repeats((s.get("text") or "").strip())
        if txt:
            segs.append((st, en, txt))
    return segs


def diarize_turns(wav, hf_token, model="pyannote/speaker-diarization-community-1"):
    """Speaker-diarize one channel -> list of (start, end, speaker_id), or None.

    Returns None (and logs why) on any problem — missing pyannote/torch, no token,
    gated-model access denied, or a runtime failure — so the caller transparently
    falls back to a single label. Never raises.
    """
    import os

    try:
        from pyannote.audio import Pipeline
    except Exception as e:
        log(f"Diarization off (pyannote.audio not installed: {e}). Using a single label.")
        return None
    # Prefer MEETINGS_HF_TOKEN; fall back to a cached `huggingface-cli login` or the
    # HF_TOKEN / HUGGING_FACE_HUB_TOKEN env vars (get_token resolves all of these).
    token = hf_token or None
    if not token:
        try:
            from huggingface_hub import get_token

            token = get_token()
        except Exception:
            token = None
    if not token:
        log("Diarization off (no HF credential — set MEETINGS_HF_TOKEN or run "
            "huggingface-cli login). Using a single label.")
        return None
    try:
        pipeline = Pipeline.from_pretrained(model, token=token)
    except Exception as e:
        log(f"Diarization off (model unavailable — token/gated-access? {e}). Single label.")
        return None
    if pipeline is None:  # pyannote returns None when gated-model access isn't granted
        log("Diarization off (model access not granted — accept the gated model). Single label.")
        return None
    # CPU by default for reliability; set MEETINGS_DIARIZE_DEVICE=mps to try the GPU.
    try:
        import torch

        pipeline.to(torch.device(os.environ.get("MEETINGS_DIARIZE_DEVICE", "cpu")))
    except Exception:
        pass
    try:
        diary = pipeline(str(wav))
    except Exception as e:
        log(f"Diarization failed at runtime ({e}). Using a single label.")
        return None
    # pyannote 4.x returns a DiarizeOutput; its exclusive_speaker_diarization is the
    # non-overlapping track built for downstream transcription (ideal for per-segment
    # attribution). Older/legacy versions return an Annotation directly.
    ann = getattr(diary, "exclusive_speaker_diarization", None)
    if ann is None:
        ann = getattr(diary, "speaker_diarization", diary)
    turns = [(float(seg.start), float(seg.end), spk)
             for seg, _, spk in ann.itertracks(yield_label=True)]
    return turns or None


def speaker_for(start, end, turns):
    """The diarized speaker_id whose turn overlaps [start,end] most, or None."""
    best, best_overlap = None, 0.0
    for ts, te, spk in turns:
        overlap = min(end, te) - max(start, ts)
        if overlap > best_overlap:
            best, best_overlap = spk, overlap
    return best


def label_right_segments(segs, turns, base_label):
    """Map right-channel (start,end,text) segments to per-speaker labels.

    With diarization turns, each segment gets "<base_label> N" (N assigned in order
    of first appearance); unmatched segments keep the bare base label. Returns
    (labelled list of (start,label,text), distinct speaker count).
    """
    if not turns:
        return [(st, base_label, txt) for st, _, txt in segs], 0
    order, labelled = {}, []
    for st, en, txt in segs:
        spk = speaker_for(st, en, turns)
        if spk is None:
            labelled.append((st, base_label, txt))
            continue
        if spk not in order:
            order[spk] = len(order) + 1
        labelled.append((st, f"{base_label} {order[spk]}", txt))
    return labelled, len(order)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("audio")
    p.add_argument("--out-dir", required=True)
    p.add_argument("--model", required=True)
    p.add_argument("--lang", default="en")
    p.add_argument("--label-left", default="Me")
    p.add_argument("--label-right", default="Them")
    p.add_argument("--no-speech-threshold", type=float, default=0.6,
                   help="drop segments whose no_speech_prob is >= this")
    p.add_argument("--silence-dbfs", type=float, default=-50.0,
                   help="drop segments whose audio RMS is below this dBFS (silence hallucinations)")
    p.add_argument("--diarize", default="auto", choices=["auto", "off"],
                   help="auto = label individual Them speakers when pyannote+token available")
    p.add_argument("--hf-token", default="",
                   help="Hugging Face token for the pyannote diarization model")
    p.add_argument("--diarize-model", default="pyannote/speaker-diarization-community-1",
                   help="pyannote pipeline repo for diarization (4.x flagship by default)")
    args = p.parse_args()

    audio = Path(args.audio).expanduser()
    if not audio.exists():
        log(f"Audio not found: {audio}")
        sys.exit(1)

    ch = channel_count(audio)
    log(f"Audio has {ch} channel(s).")

    segments = []
    speaker_count = 0
    t0 = time.perf_counter()
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        if ch >= 2:
            left, right = td / "left.wav", td / "right.wav"
            extract_channel(audio, 0, left)
            extract_channel(audio, 1, right)
            log(f"Transcribing left channel ({args.label_left})…")
            left_segs = transcribe_channel(left, args.model, args.lang,
                                           args.no_speech_threshold, args.silence_dbfs)
            segments += [(st, args.label_left, txt) for st, _, txt in left_segs]
            log(f"Transcribing right channel ({args.label_right})…")
            right_segs = transcribe_channel(right, args.model, args.lang,
                                            args.no_speech_threshold, args.silence_dbfs)
            # Attribute individual remote speakers on the Them channel.
            turns = None
            if args.diarize == "auto" and right_segs:
                log("Diarizing the Them channel for individual speakers…")
                turns = diarize_turns(right, args.hf_token, args.diarize_model)
            labelled, speaker_count = label_right_segments(right_segs, turns, args.label_right)
            segments += labelled
            if speaker_count:
                log(f"Identified {speaker_count} speaker(s) on the Them channel.")
        else:
            mono = td / "mono.wav"
            extract_channel(audio, 0, mono)
            log("Transcribing single channel…")
            mono_segs = transcribe_channel(mono, args.model, args.lang,
                                           args.no_speech_threshold, args.silence_dbfs)
            segments += [(st, args.label_left, txt) for st, _, txt in mono_segs]
    dt = time.perf_counter() - t0

    segments.sort(key=lambda x: x[0])

    out_dir = Path(args.out_dir).expanduser()
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{audio.stem}.transcript.md"

    speakers_note = (f" · {speaker_count} Them speaker(s) identified"
                     if speaker_count > 1 else "")
    lines = [
        f"# Transcript — {audio.stem}", "",
        f"*Transcribed locally with {args.model} in {hms(dt)}{speakers_note}*", "",
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
