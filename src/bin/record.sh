#!/bin/bash
# Component 1: toggle a stereo meeting recording.
#   Left channel  = your microphone           -> "Me"
#   Right channel = system audio (process tap) -> "Them"
# Run once to start, run again to stop.
#
# Capture is done by MeetingCapture.app (a Core Audio process tap clocked by the mic;
# no BlackHole, no Audio MIDI Setup — see docs/adr/0001-*.md). It is launched via `open`
# so the signed bundle is its OWN TCC responsible process and its
# NSMicrophoneUsageDescription applies — the tap is gated by the Microphone service, and
# running it directly under Alfred makes *Alfred* responsible (no usage string), so the
# tap returns silence. Because `open` detaches the process, we track/stop it by the unique
# recording filename in its argv (pgrep / pkill -INT), not a pid.
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$ROOT/config.sh"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

mkdir -p "$SUPPORT" "$OUTPUT_DIR"
STATEFILE="$SUPPORT/recording.state"   # single line: the recording's audio path

rec_pids() { [ -n "$1" ] && pgrep -f "$1" 2>/dev/null; }   # processes whose argv contains $1

is_recording() {
  local audio
  [ -f "$STATEFILE" ] || return 1
  audio="$(sed -n '1p' "$STATEFILE" 2>/dev/null)"
  [ -n "$audio" ] && [ -n "$(rec_pids "$(basename "$audio")")" ]
}

stop_recording() {
  local audio base
  audio="$(sed -n '1p' "$STATEFILE" 2>/dev/null || true)"
  base="$(basename "$audio" 2>/dev/null || true)"
  if [ -n "$base" ]; then
    pkill -INT -f "$base" 2>/dev/null || true        # SIGINT lets MeetingCapture finalize the m4a
    for _ in $(seq 1 30); do [ -z "$(rec_pids "$base")" ] && break; sleep 0.5; done
    # Dismiss the menu-bar indicator for this take (stamp = base minus rec_ / .m4a).
    local stamp="${base#rec_}"; stamp="${stamp%.m4a}"
    [ -n "$stamp" ] && pkill -f "RecIndicator.app.*$stamp" 2>/dev/null || true
  fi
  rm -f "$STATEFILE"
  if [ -n "$audio" ] && [ -f "$audio" ]; then
    echo "✅ Saved: $audio"
  else
    echo "⏹ Recording stopped (no file written — if a mic prompt appeared, allow it and retry)."
  fi
}

start_recording() {
  if [ ! -d "$CAPTURE_APP" ]; then
    echo "❌ Capture app missing ($CAPTURE_APP). Run setup/install.sh." >&2
    exit 1
  fi

  # No recording is active on this path, so any surviving indicator is an orphan from an
  # earlier failed start. Clear it now so indicators never pile up in the menu bar.
  pkill -f "RecIndicator.app" 2>/dev/null || true

  local stamp audio log
  stamp="$(date +%Y-%m-%d_%H-%M-%S)"
  audio="$OUTPUT_DIR/rec_$stamp.m4a"
  log="$SUPPORT/MeetingCapture.log"
  printf '%s\n' "$audio" > "$STATEFILE"

  # Optional: scope the tap to one app (config THEM_APP); otherwise tap all system audio.
  local scope=()
  if [ -n "$THEM_APP" ]; then
    local them_pid
    them_pid="$(pgrep -n -f "$THEM_APP" 2>/dev/null || true)"
    if [ -n "$them_pid" ]; then
      scope=(--pid "$them_pid")
    else
      echo "⚠️ Them app \"$THEM_APP\" not running — capturing all system audio." >&2
    fi
  fi

  # Truncate the log so we only read THIS run's start outcome (the capture app appends).
  : > "$log"

  # Launched via `open` for TCC responsibility (above). MeetingCapture writes
  # mic -> left ("Me"), tap -> right ("Them"), runs until SIGINT, and confirms its own
  # start before recording.
  open -n -a "$CAPTURE_APP" --args \
    --out "$audio" --mic "$MIC_DEVICE" "${scope[@]}" \
    --log "$log"

  # Wait for MeetingCapture to CONFIRM its start (an IOProc actually fired) — not merely
  # for the process to exist. It spends up to ~4.5s in its start-retry loop before logging
  # "recording (start confirmed)" or "FAIL"; launching the indicator any earlier leaks it
  # whenever the start ultimately fails (the cause of stray menu-bar indicators).
  local confirmed="" maxpolls=40 i=0 primed=""               # ~10s ceiling (> 4.5s window)
  while [ "$i" -lt "$maxpolls" ]; do
    if grep -q "recording (start confirmed)" "$log" 2>/dev/null; then confirmed=1; break; fi
    if grep -qE "^(FAIL|FATAL):" "$log" 2>/dev/null; then break; fi
    # First-run priming: on a machine that has never granted system-audio capture,
    # MeetingCapture shows the "System Audio Recording" prompt and waits up to 120s for it.
    # Detect its request line and extend our ceiling once (a one-time prime, like the mic
    # grant) so the user has time to click Allow instead of us killing the prompt at ~10s.
    if [ -z "$primed" ] && grep -q "requesting System Audio Recording permission" "$log" 2>/dev/null; then
      primed=1; maxpolls=520                                 # ~130s ceiling (> the app's 120s wait)
      echo "🔐 First run: click Allow on the 'System Audio Recording' prompt to enable Them capture…" >&2
    fi
    i=$((i + 1)); sleep 0.25
  done

  if [ -z "$confirmed" ]; then
    pkill -INT -f "$(basename "$audio")" 2>/dev/null || true # stop a hung/late starter
    rm -f "$STATEFILE"
    echo "❌ Recorder didn't start. If macOS shows a 'Microphone' or 'System Audio Recording' prompt for 'AlfredMeetings Capture', click Allow, then run rec again." >&2
    exit 1
  fi
  # Confirmed recording → show the menu-bar "recording now" indicator (best-effort; never
  # blocks). The stamp is passed so stop_recording can find/kill this app by argv match.
  if [ -d "$INDICATOR_APP" ]; then
    open -n -a "$INDICATOR_APP" --args --stamp "$stamp" --stop "$ROOT/bin/record.sh" >/dev/null 2>&1 || true
  fi
  echo "🔴 Recording… Run 'rec' again to stop."
}

if is_recording; then
  stop_recording
else
  rm -f "$STATEFILE" 2>/dev/null || true   # clear any stale state
  start_recording
fi
