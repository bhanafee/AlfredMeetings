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
chmod +x "$SRC"/bin/*.sh 2>/dev/null || true

( cd "$SRC" && zip -r -X "$DIST/$NAME" . -x '.DS_Store' -x '*/__pycache__/*' >/dev/null )
echo "Built $DIST/$NAME"
