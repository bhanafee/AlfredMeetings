#!/bin/bash
# Shared configuration for AlfredMeetings.
# Every value can be overridden by an environment variable (e.g. set in Alfred's
# workflow environment variables, or exported in your shell). Edit the defaults
# here to taste.

# --- Where recordings, transcripts, and notes are written -------------------
OUTPUT_DIR="${MEETINGS_OUTPUT_DIR:-$HOME/Desktop/Meeting Notes}"

# --- Transcription (mlx-whisper) --------------------------------------------
WHISPER_MODEL="${MEETINGS_WHISPER_MODEL:-mlx-community/whisper-large-v3-turbo}"
WHISPER_LANG="${MEETINGS_WHISPER_LANG:-en}"

# --- Speaker attribution on the "Them" channel (pyannote.audio) -------------
# DIARIZE=auto labels each remote speaker (Them 1, Them 2, …) when pyannote and a
# Hugging Face token are available, and silently falls back to a single "Them"
# otherwise; DIARIZE=off disables it. The token needs one-time acceptance of the
# gated model below at huggingface.co/<model> (see README). The default is the
# pyannote.audio 4.x flagship pipeline; override if you pin a different version.
DIARIZE="${MEETINGS_DIARIZE:-auto}"
HF_TOKEN="${MEETINGS_HF_TOKEN:-}"
DIARIZE_MODEL="${MEETINGS_DIARIZE_MODEL:-pyannote/speaker-diarization-community-1}"

# --- Notes processing (local Ollama / any OpenAI-compatible endpoint) -------
LLM_MODEL="${MEETINGS_LLM_MODEL:-qwen3:4b-instruct}"
LLM_BASE_URL="${MEETINGS_LLM_BASE_URL:-http://localhost:11434/v1}"
LLM_API_KEY="${MEETINGS_LLM_API_KEY:-not-needed}"

# --- Audio capture ----------------------------------------------------------
# The far side ("Them") is captured with a Core Audio process tap (no BlackHole,
# no Audio MIDI Setup); the microphone ("Me") is the aggregate's clock master.
# See docs/adr/0001-system-audio-capture-via-core-audio-process-tap.md.
#
# Microphone choice (jabra|builtin|bluetooth, or "auto") resolves to a PHYSICAL
# input device name, which MeetingCapture matches by name (or CoreAudio UID).
# "auto" picks the first currently-connected device by priority:
#   Jabra -> Built-in -> Bluetooth
# Unlike the old BlackHole path there is NO output rerouting — you keep your normal
# output device and volume throughout.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"   # so SwitchAudioSource resolves

INPUT_SOURCE="${MEETINGS_INPUT_SOURCE:-auto}"

# Physical device names (override if yours differ).
DEV_JABRA="${MEETINGS_DEV_JABRA:-Jabra Engage 75}"
DEV_BUILTIN_MIC="${MEETINGS_DEV_BUILTIN_MIC:-MacBook Air Microphone}"
DEV_BLUETOOTH="${MEETINGS_DEV_BLUETOOTH:-Headphones}"

_connected() {  # _connected input|output "Device Name"
  SwitchAudioSource -a -t "$1" 2>/dev/null | grep -qxF "$2"
}

# Resolve the mic choice to a physical device name (auto = first connected by priority).
_input_device() {
  case "$INPUT_SOURCE" in
    jabra)     printf '%s' "$DEV_JABRA" ;;
    builtin)   printf '%s' "$DEV_BUILTIN_MIC" ;;
    bluetooth) printf '%s' "$DEV_BLUETOOTH" ;;
    *)  # auto: Jabra -> Built-in -> Bluetooth
        if   _connected input "$DEV_JABRA";       then printf '%s' "$DEV_JABRA"
        elif _connected input "$DEV_BUILTIN_MIC"; then printf '%s' "$DEV_BUILTIN_MIC"
        elif _connected input "$DEV_BLUETOOTH";   then printf '%s' "$DEV_BLUETOOTH"
        else printf '%s' "$DEV_BUILTIN_MIC"; fi ;;   # built-in is always present
  esac
}

# Mic passed to MeetingCapture --mic (a CoreAudio UID or a name substring).
# Advanced override wins; otherwise the Microphone choice above.
MIC_DEVICE="${MEETINGS_MIC_DEVICE:-$(_input_device)}"

# "Them" scope: leave THEM_APP blank to tap ALL system audio, or set it to the
# meeting app's process name (e.g. "zoom.us", "Microsoft Teams") to capture only that
# app — record.sh resolves it to a pid for MeetingCapture --pid.
THEM_APP="${MEETINGS_THEM_APP:-}"

# --- Internal: venv + state live OUTSIDE the (re-importable) workflow bundle -
# Pin to a fixed path (NOT $alfred_workflow_data): install.sh runs from the
# terminal where that var is unset, so it must resolve to the same place the
# scripts use when Alfred runs them — otherwise the venv install.sh built can't
# be found under Alfred. Override with MEETINGS_SUPPORT if you must relocate it.
SUPPORT="${MEETINGS_SUPPORT:-$HOME/Library/Application Support/AlfredMeetings}"
VENV="$SUPPORT/venv"
PY="$VENV/bin/python3"

# The capture helper (built + ad-hoc-signed by setup/install.sh). It taps system audio
# + the mic and writes the stereo .m4a. record.sh launches it via `open` so it becomes
# its OWN TCC-responsible process — the tap is gated by the Microphone service, and the
# bundle carries NSMicrophoneUsageDescription. Launching the binary directly makes the
# PARENT (Alfred/terminal) responsible, which has no usage string, so the tap silently
# returns zeros (or macOS aborts the capture). See docs/adr/0001-*.md.
CAPTURE_APP="${MEETINGS_CAPTURE_APP:-$SUPPORT/MeetingCapture.app}"

# Menu-bar "recording now" indicator (a native status-bar app built by install.sh).
# record.sh launches it on start and kills it on stop; missing is non-fatal.
INDICATOR_APP="${MEETINGS_INDICATOR_APP:-$SUPPORT/RecIndicator.app}"
