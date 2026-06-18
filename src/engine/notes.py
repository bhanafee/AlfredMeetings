#!/usr/bin/env python3
"""notes.py — process a transcript with a local Ollama (OpenAI-compatible) model.

Reads a Markdown transcript, applies one of several modes, writes a new Markdown
file next to it (in --out-dir), and prints ONLY the output path on stdout. All
progress goes to stderr so the caller can capture the result cleanly.
"""
import argparse
import re
import sys
import time
from pathlib import Path

MODES = {
    "clean": "clean.txt",
    "summary": "summary.txt",
    "minutes": "minutes.txt",
}


def log(msg):  # progress -> stderr
    print(msg, file=sys.stderr, flush=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("transcript")
    p.add_argument("--mode", required=True, help="clean | summary | minutes | custom")
    p.add_argument("--custom-prompt", default="", help="system prompt for --mode custom")
    p.add_argument("--model", required=True)
    p.add_argument("--base-url", required=True)
    p.add_argument("--api-key", default="not-needed")
    p.add_argument("--prompts-dir", required=True)
    p.add_argument("--out-dir", required=True)
    args = p.parse_args()

    src = Path(args.transcript).expanduser()
    if not src.exists():
        log(f"Transcript not found: {src}")
        sys.exit(1)
    text = src.read_text(encoding="utf-8")

    if args.mode == "custom":
        system_prompt = args.custom_prompt.strip()
        if not system_prompt:
            log("custom mode requires a non-empty --custom-prompt")
            sys.exit(1)
        suffix = "custom"
    elif args.mode in MODES:
        pf = Path(args.prompts_dir) / MODES[args.mode]
        if not pf.exists():
            log(f"Prompt file missing: {pf}")
            sys.exit(1)
        system_prompt = pf.read_text(encoding="utf-8").strip()
        suffix = args.mode
    else:
        log(f"Unknown mode: {args.mode} (use clean|summary|minutes|custom)")
        sys.exit(1)

    from openai import OpenAI

    client = OpenAI(base_url=args.base_url, api_key=args.api_key or "x")
    log(f"Processing ({args.mode}) with {args.model}…")
    t0 = time.perf_counter()
    try:
        resp = client.chat.completions.create(
            model=args.model,
            temperature=0.2,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": text},
            ],
        )
    except Exception as e:  # network/model errors -> clean message for the wrapper
        log(f"LLM request failed: {e}")
        sys.exit(1)
    dt = time.perf_counter() - t0

    out = (resp.choices[0].message.content or "").strip()
    # Some local models (e.g. qwen3 thinking variants) wrap reasoning in <think>…</think>.
    out = re.sub(r"<think>.*?</think>\s*", "", out, flags=re.DOTALL).strip()
    if not out:
        log("Model returned empty output.")
        sys.exit(1)

    out_dir = Path(args.out_dir).expanduser()
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{src.stem}.{suffix}.md"
    header = (
        f"# {suffix.title()} — {src.stem}\n\n"
        f"*Generated locally with {args.model} in {dt:.0f}s*\n\n"
    )
    out_path.write_text(header + out + "\n", encoding="utf-8")

    log(f"Done in {dt:.0f}s")
    print(str(out_path))  # the ONLY thing on stdout: the output file path


if __name__ == "__main__":
    main()
