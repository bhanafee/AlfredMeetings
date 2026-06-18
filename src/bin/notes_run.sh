#!/bin/bash
# Bridges the `notes` Script Filter selection to notes.sh.
# Arg is either a bare mode ("minutes"/"summary"/"clean") or "custom\t<instruction>".
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

ARG="$1"
MODE="${ARG%%$'\t'*}"
if [ "$MODE" = "custom" ]; then
  export CUSTOM_PROMPT="${ARG#*$'\t'}"
fi

RESULT="$("$ROOT/bin/notes.sh" "$MODE")"
[ -n "$RESULT" ] && [ -f "$RESULT" ] && open "$RESULT"
echo "$RESULT"
