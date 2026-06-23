#!/bin/bash
# Build dist/AlfredMeetings.alfredworkflow from src/.
# The contents of src/ become the root of the workflow bundle.
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/src"
DIST="$ROOT/dist"
NAME="AlfredMeetings.alfredworkflow"

mkdir -p "$DIST"
rm -f "$DIST/$NAME"

# Ensure scripts are executable inside the bundle.
chmod +x "$SRC"/bin/*.sh "$SRC"/bin/meetings 2>/dev/null || true

# capture/ ships the source for reference; install.sh compiles it from the repo, not the
# bundle. The spike/ exclude is a guard — that throwaway proof-of-concept lives only on
# the spike/system-audio-tap branch and must never reach the packaged workflow.
( cd "$SRC" && zip -r -X "$DIST/$NAME" . \
    -x '.DS_Store' -x '*/__pycache__/*' -x 'spike/*' >/dev/null )
echo "Built $DIST/$NAME"
