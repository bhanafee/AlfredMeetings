#!/bin/bash
# Component 1: toggle a stereo meeting recording.
#   Left channel  = your microphone          -> "Me"
#   Right channel = system audio (BlackHole)  -> "Them"
# Run once to start, run again to stop.
#
# The recorder runs via `open` so the MicCapture.app bundle is its OWN TCC
# responsible process and its NSMicrophoneUsageDescription applies. Running ffmpeg
# directly under Alfred makes *Alfred* the responsible process — and Alfred has no
# mic usage description, so macOS aborts the capture (SIGABRT). See setup/install.sh.
# Because `open` detaches the process, we track it by the unique recording filename
# in its argv rather than a pid.
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$ROOT/config.sh"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

mkdir -p "$SUPPORT" "$OUTPUT_DIR"
STATEFILE="$SUPPORT/recording.state"   # line1: original output device, line2: audio path

rec_pids() { [ -n "$1" ] && pgrep -f "$1" 2>/dev/null; }   # processes whose argv contains $1

is_recording() {
  local audio
  [ -f "$STATEFILE" ] || return 1
  audio="$(sed -n '2p' "$STATEFILE" 2>/dev/null)"
  [ -n "$audio" ] && [ -n "$(rec_pids "$(basename "$audio")")" ]
}

stop_recording() {
  local orig audio base
  orig="$(sed -n '1p' "$STATEFILE" 2>/dev/null || true)"
  audio="$(sed -n '2p' "$STATEFILE" 2>/dev/null || true)"
  base="$(basename "$audio" 2>/dev/null || true)"
  if [ -n "$base" ]; then
    pkill -INT -f "$base" 2>/dev/null || true        # SIGINT lets ffmpeg finalize the m4a
    for _ in $(seq 1 30); do [ -z "$(rec_pids "$base")" ] && break; sleep 0.5; done
  fi
  [ -n "$orig" ] && SwitchAudioSource -t output -s "$orig" >/dev/null 2>&1 || true
  rm -f "$STATEFILE"
  if [ -n "$audio" ] && [ -f "$audio" ]; then
    echo "✅ Saved: $audio"
  else
    echo "⏹ Recording stopped (no file written — if a mic prompt appeared, allow it and retry)."
  fi
}

start_recording() {
  if ! SwitchAudioSource -a -t input 2>/dev/null | grep -qF "$CAPTURE_DEVICE"; then
    echo "⚠️ Input device \"$CAPTURE_DEVICE\" not found — see setup/audio-setup.md." >&2
    exit 1
  fi
  if [ ! -d "$MIC_APP" ]; then
    echo "❌ Mic-capture app missing ($MIC_APP). Run setup/install.sh." >&2
    exit 1
  fi

  local orig stamp audio
  orig="$(SwitchAudioSource -c -t output 2>/dev/null || true)"
  SwitchAudioSource -t output -s "$OUTPUT_DEVICE" >/dev/null 2>&1 || true

  stamp="$(date +%Y-%m-%d_%H-%M-%S)"
  audio="$OUTPUT_DIR/rec_$stamp.m4a"
  printf '%s\n%s\n' "$orig" "$audio" > "$STATEFILE"

  # Aggregate presents c0 = mic, c1/c2 = BlackHole L/R -> stereo: left = mic ("Me"),
  # right = system audio ("Them"). Launched via `open` for TCC responsibility (above).
  open -n -a "$MIC_APP" --args -y -hide_banner -loglevel warning \
    -f avfoundation -i ":$CAPTURE_DEVICE" \
    -af "pan=stereo|c0=c0|c1=0.5*c1+0.5*c2" \
    -ar 48000 -c:a aac -b:a 128k "$audio"

  for _ in $(seq 1 10); do [ -n "$(rec_pids "$(basename "$audio")")" ] && break; sleep 0.3; done
  if ! is_recording; then
    [ -n "$orig" ] && SwitchAudioSource -t output -s "$orig" >/dev/null 2>&1 || true
    rm -f "$STATEFILE"
    echo "❌ Recorder didn't start. If macOS shows a mic prompt for 'AlfredMeetings Mic Capture', click Allow, then run rec again." >&2
    exit 1
  fi
  echo "🔴 Recording… (if macOS asks, allow mic access for AlfredMeetings Mic Capture). Run 'rec' again to stop."
}

if is_recording; then
  stop_recording
else
  rm -f "$STATEFILE" 2>/dev/null || true   # clear any stale state
  start_recording
fi
