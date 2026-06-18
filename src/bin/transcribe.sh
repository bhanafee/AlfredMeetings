#!/bin/bash
# Component 2: transcribe a (stereo) recording into a speaker-labeled Markdown
# transcript.
#
# Usage: transcribe.sh [audio_file]
# If audio_file is omitted, the newest rec_*.m4a in OUTPUT_DIR is used.
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$ROOT/config.sh"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

AUDIO="${1:-}"
# Any argument that isn't an existing file — empty (manual `transcribe`), or the
# rec keyword's status text when auto-chained after recording — falls back to the
# newest recording.
if [ ! -f "$AUDIO" ]; then
  AUDIO="$(/bin/ls -t "$OUTPUT_DIR"/rec_*.m4a 2>/dev/null | head -1 || true)"
fi
# This step is wired to the rec keyword, which also fires on START. If the newest
# recording is still being written, there's nothing to transcribe yet — stay silent
# (no stdout) so the "Transcript ready" notification doesn't fire on start.
if [ -n "$AUDIO" ] && pgrep -f "$(basename "$AUDIO")" >/dev/null 2>&1; then
  exit 0
fi
if [ -z "$AUDIO" ] || [ ! -f "$AUDIO" ]; then
  echo "No audio found (looked for rec_*.m4a in: $OUTPUT_DIR). Record something first." >&2
  exit 1
fi
if [ ! -x "$PY" ]; then
  echo "Python env missing — run setup/install.sh first." >&2
  exit 1
fi

"$PY" "$ROOT/engine/transcribe.py" "$AUDIO" \
  --out-dir "$OUTPUT_DIR" \
  --model "$WHISPER_MODEL" \
  --lang "$WHISPER_LANG"
