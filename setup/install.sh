#!/bin/bash
# One-time setup for AlfredMeetings: a Python venv with the transcription and
# LLM-client libraries. This is the pip side only and needs no Homebrew.
#
# Homebrew packages (ffmpeg, switchaudio-osx, blackhole-2ch, ollama) and the
# Audio MIDI devices must be set up separately — see ../README.md and
# ./audio-setup.md.
set -e

SUPPORT="${alfred_workflow_data:-$HOME/Library/Application Support/AlfredMeetings}"
VENV="$SUPPORT/venv"
mkdir -p "$SUPPORT"

echo ">>> Creating Python venv at: $VENV"
python3 -m venv "$VENV"
"$VENV/bin/pip" install --quiet --upgrade pip
echo ">>> Installing mlx-whisper + openai (this downloads a few hundred MB)…"
"$VENV/bin/pip" install --quiet mlx-whisper openai

echo ">>> Checking external tools:"
for t in ffmpeg ollama SwitchAudioSource; do
  if command -v "$t" >/dev/null 2>&1; then
    echo "  ok:      $t"
  else
    echo "  MISSING: $t  (see README.md)"
  fi
done
if SwitchAudioSource -a 2>/dev/null | grep -qi blackhole; then
  echo "  ok:      BlackHole audio device"
else
  echo "  MISSING: BlackHole audio device  (see audio-setup.md)"
fi

echo ">>> Done. Output dir: ${MEETINGS_OUTPUT_DIR:-$HOME/Desktop/Meeting Notes}"
