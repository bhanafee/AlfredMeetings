#!/bin/bash
# Component 1: toggle a stereo meeting recording.
#   Left channel  = your microphone          -> "Me"
#   Right channel = system audio (BlackHole)  -> "Them"
# Run once to start, run again to stop. Designed to be invoked from Alfred, so it
# returns immediately on start (ffmpeg runs detached) and prints a one-line status
# on stdout for the notification.
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$ROOT/config.sh"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

mkdir -p "$SUPPORT" "$OUTPUT_DIR"
PIDFILE="$SUPPORT/recording.pid"
STATEFILE="$SUPPORT/recording.state"   # line1: original output device, line2: audio path
LOG="$SUPPORT/ffmpeg.log"

is_recording() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; }

stop_recording() {
  local pid orig audio
  pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  orig="$(sed -n '1p' "$STATEFILE" 2>/dev/null || true)"
  audio="$(sed -n '2p' "$STATEFILE" 2>/dev/null || true)"
  if [ -n "$pid" ]; then
    kill -INT "$pid" 2>/dev/null || true              # SIGINT lets ffmpeg finalize the m4a
    for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
  fi
  [ -n "$orig" ] && SwitchAudioSource -t output -s "$orig" >/dev/null 2>&1 || true
  rm -f "$PIDFILE" "$STATEFILE"
  if [ -n "$audio" ] && [ -f "$audio" ]; then
    echo "✅ Saved: $audio"
  else
    echo "⏹ Recording stopped (no file written — see $LOG)."
  fi
}

start_recording() {
  if ! SwitchAudioSource -a -t input 2>/dev/null | grep -qF "$CAPTURE_DEVICE"; then
    echo "⚠️ Input device \"$CAPTURE_DEVICE\" not found — see setup/audio-setup.md." >&2
    exit 1
  fi
  local orig stamp audio
  orig="$(SwitchAudioSource -c -t output 2>/dev/null || true)"
  SwitchAudioSource -t output -s "$OUTPUT_DEVICE" >/dev/null 2>&1 || true

  stamp="$(date +%Y-%m-%d_%H-%M-%S)"
  audio="$OUTPUT_DIR/rec_$stamp.m4a"
  printf '%s\n%s\n' "$orig" "$audio" > "$STATEFILE"

  # Aggregate "Meeting Capture" presents: c0 = mic, c1/c2 = BlackHole L/R.
  # Map to stereo: left = mic ("Me"), right = system audio ("Them").
  # NOTE: if your aggregate's channel layout differs, adjust this pan filter.
  nohup ffmpeg -y -hide_banner -loglevel warning \
    -f avfoundation -i ":$CAPTURE_DEVICE" \
    -af "pan=stereo|c0=c0|c1=0.5*c1+0.5*c2" \
    -ar 48000 -c:a aac -b:a 128k "$audio" >"$LOG" 2>&1 &
  echo $! > "$PIDFILE"
  disown 2>/dev/null || true

  sleep 1
  if ! is_recording; then
    [ -n "$orig" ] && SwitchAudioSource -t output -s "$orig" >/dev/null 2>&1 || true
    rm -f "$PIDFILE"
    echo "❌ Recorder failed to start — check $LOG (mic permission for ffmpeg?)." >&2
    exit 1
  fi
  echo "🔴 Recording… run 'rec' again to stop."
}

if is_recording; then
  stop_recording
else
  rm -f "$PIDFILE"   # clear any stale pid
  start_recording
fi
