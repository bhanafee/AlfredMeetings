#!/bin/bash
# One-time setup for AlfredMeetings: a Python venv with the transcription and
# LLM-client libraries, plus the native capture + indicator helper apps.
#
# Far-side audio is captured with a Core Audio process tap (no BlackHole, no Audio MIDI
# Setup — see ../docs/adr/0001-*.md); first `rec` will prompt once for Microphone access.
# Homebrew packages (ffmpeg, switchaudio-osx, ollama) and a running Ollama are still
# needed — see ../README.md.
set -e

# Must match config.sh exactly (a fixed path, not $alfred_workflow_data) so the
# venv built here is found when Alfred runs the scripts.
SUPPORT="${MEETINGS_SUPPORT:-$HOME/Library/Application Support/AlfredMeetings}"
VENV="$SUPPORT/venv"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$SUPPORT"

echo ">>> Creating Python venv at: $VENV"
python3 -m venv "$VENV"
"$VENV/bin/pip" install --quiet --upgrade pip
echo ">>> Installing mlx-whisper + openai (this downloads a few hundred MB)…"
"$VENV/bin/pip" install --quiet mlx-whisper openai
echo ">>> Installing pyannote.audio for per-speaker Them labels (pulls PyTorch)…"
# Diarization is optional at runtime (transcribe falls back to a single "Them" if it or
# the HF token is missing), but installing it here makes the feature available. After
# this, create a free Hugging Face token, accept the gated model at
# huggingface.co/pyannote/speaker-diarization-community-1, and set MEETINGS_HF_TOKEN.
"$VENV/bin/pip" install --quiet pyannote.audio || \
  echo "  WARNING: pyannote.audio install failed — Them-side speaker labels will be off."

echo ">>> Building capture helper (MeetingCapture.app)…"
# Records the meeting as stereo (mic -> left "Me", system-audio process tap -> right
# "Them") with no BlackHole. The tap is TCC-gated by the Microphone service, so the
# bundle carries NSMicrophoneUsageDescription and record.sh launches it via `open` so it
# is its own responsible process. See ../docs/adr/0001-*.md.
CAP_SRC="$REPO_ROOT/src/capture/MeetingCapture.swift"
if command -v swiftc >/dev/null 2>&1 && [ -f "$CAP_SRC" ]; then
  CAP="$SUPPORT/MeetingCapture.app"
  rm -rf "$CAP"
  mkdir -p "$CAP/Contents/MacOS"
  if swiftc -O "$CAP_SRC" -o "$CAP/Contents/MacOS/MeetingCapture" \
       -framework CoreAudio -framework AudioToolbox 2>/dev/null; then
    cat > "$CAP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>MeetingCapture</string>
  <key>CFBundleIdentifier</key><string>com.maybeitssquid.alfredmeetings.capture</string>
  <key>CFBundleName</key><string>AlfredMeetings Capture</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>AlfredMeetings records your meeting audio (your mic and the far side) locally for transcription.</string>
</dict>
</plist>
PLIST
    if codesign --force --sign - --identifier com.maybeitssquid.alfredmeetings.capture "$CAP" 2>/dev/null; then
      echo "  ok:      $CAP (signed)"
      echo "  NOTE:    first 'rec' will prompt once for Microphone access — click Allow."
    else
      echo "  WARNING: codesign failed for $CAP — capture may not get the mic grant."
    fi
  else
    echo "  WARNING: swiftc failed to build the capture helper — recording will not work."
  fi
else
  echo "  MISSING: swiftc (Xcode CLT) — cannot build the capture helper (see README.md)."
fi

echo ">>> Building menu-bar recording indicator…"
# A tiny native status-bar app shown while recording (red ● in the menu bar, click to
# stop). record.sh launches it on start and kills it on stop. No special entitlement is
# needed — it never opens the mic.
SWIFT_SRC="$REPO_ROOT/src/indicator/RecIndicator.swift"
if command -v swiftc >/dev/null 2>&1 && [ -f "$SWIFT_SRC" ]; then
  IND="$SUPPORT/RecIndicator.app"
  rm -rf "$IND"
  mkdir -p "$IND/Contents/MacOS"
  if swiftc "$SWIFT_SRC" -o "$IND/Contents/MacOS/RecIndicator" 2>/dev/null; then
    cat > "$IND/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>RecIndicator</string>
  <key>CFBundleIdentifier</key><string>com.maybeitssquid.alfredmeetings.recindicator</string>
  <key>CFBundleName</key><string>AlfredMeetings Recording</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
    if codesign --force --sign - --identifier com.maybeitssquid.alfredmeetings.recindicator "$IND" 2>/dev/null; then
      echo "  ok:      $IND (signed)"
    else
      echo "  WARNING: codesign failed for $IND — indicator may not launch."
    fi
  else
    echo "  WARNING: swiftc failed to build the indicator — recording still works, just no menu-bar dot."
  fi
else
  echo "  SKIP:    swiftc not found — skipping the menu-bar indicator (recording still works)."
fi

echo ">>> Installing 'meetings' CLI to ~/.local/bin…"
mkdir -p "$HOME/.local/bin"
ln -sf "$REPO_ROOT/src/bin/meetings" "$HOME/.local/bin/meetings"
echo "  ok:      $HOME/.local/bin/meetings -> $REPO_ROOT/src/bin/meetings"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "  NOTE:    ~/.local/bin is not on your PATH — add it to use 'meetings' directly." ;;
esac

echo ">>> Checking external tools:"
for t in ffmpeg ollama SwitchAudioSource; do
  if command -v "$t" >/dev/null 2>&1; then
    echo "  ok:      $t"
  else
    echo "  MISSING: $t  (see README.md)"
  fi
done
# BlackHole is NO LONGER required (the process tap replaced it). Only note it if present.
if SwitchAudioSource -a 2>/dev/null | grep -qi blackhole; then
  echo "  note:    BlackHole present — not used anymore; safe to remove (see audio-setup.md)."
fi

echo ">>> Done. Output dir: ${MEETINGS_OUTPUT_DIR:-$HOME/Desktop/Meeting Notes}"
