#!/bin/bash
# Component 3: process a transcript through the local LLM.
#
# Usage: notes.sh <mode> [transcript_file]
#   mode: clean | summary | minutes | custom
#
# If transcript_file is omitted, the most recent *.transcript.md in OUTPUT_DIR is
# used. For custom mode, the instruction text is read from $CUSTOM_PROMPT (Alfred
# sets this from the user's typed argument).
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$ROOT/config.sh"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

MODE="${1:?usage: notes.sh <clean|summary|minutes|custom> [transcript]}"
TRANSCRIPT="${2:-}"

if [ -z "$TRANSCRIPT" ]; then
  # newest transcript in the output dir
  TRANSCRIPT="$(/bin/ls -t "$OUTPUT_DIR"/*.transcript.md 2>/dev/null | head -1 || true)"
fi
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  echo "No transcript found (looked in: $OUTPUT_DIR). Run 'transcribe' first." >&2
  exit 1
fi

if [ ! -x "$PY" ]; then
  echo "Python env missing — run setup/install.sh first." >&2
  exit 1
fi

"$PY" "$ROOT/engine/notes.py" "$TRANSCRIPT" \
  --mode "$MODE" \
  --custom-prompt "${CUSTOM_PROMPT:-}" \
  --model "$LLM_MODEL" \
  --base-url "$LLM_BASE_URL" \
  --api-key "$LLM_API_KEY" \
  --prompts-dir "$ROOT/engine/prompts" \
  --out-dir "$OUTPUT_DIR"
