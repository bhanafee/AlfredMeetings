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

# --- Notes processing (local Ollama / any OpenAI-compatible endpoint) -------
LLM_MODEL="${MEETINGS_LLM_MODEL:-qwen3:4b-instruct}"
LLM_BASE_URL="${MEETINGS_LLM_BASE_URL:-http://localhost:11434/v1}"
LLM_API_KEY="${MEETINGS_LLM_API_KEY:-not-needed}"

# --- Audio device selection -------------------------------------------------
# Microphone (input) and listening device (output) are chosen independently from
# Alfred's Configure Workflow panel. Each is jabra|builtin|bluetooth, or "auto"
# (the default) which picks the first *currently connected* device by priority:
#   input  : Jabra -> Built-in -> Bluetooth
#   output : Jabra -> Bluetooth -> Built-in
# Each choice resolves to a physical device, then to the aggregate/multi-output
# you build once in Audio MIDI Setup, named by an exact convention:
#   * aggregate INPUT  "Input Capture (<mic device>)"    = that mic + BlackHole 2ch
#                                                          (mic=ch0/"Me", BH=ch1-2/"Them")
#   * multi-OUTPUT     "Output Capture (<output device>)" = that device + BlackHole 2ch
# e.g. "Input Capture (Jabra Engage 75)", "Output Capture (MacBook Air Speakers)".
# The parenthesized part must match the real device name exactly.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"   # so SwitchAudioSource resolves

INPUT_SOURCE="${MEETINGS_INPUT_SOURCE:-auto}"
OUTPUT_SOURCE="${MEETINGS_OUTPUT_SOURCE:-auto}"

# Physical device names (override if yours differ).
DEV_JABRA="${MEETINGS_DEV_JABRA:-Jabra Engage 75}"
DEV_BUILTIN_MIC="${MEETINGS_DEV_BUILTIN_MIC:-MacBook Air Microphone}"
DEV_BUILTIN_OUT="${MEETINGS_DEV_BUILTIN_OUT:-MacBook Air Speakers}"
DEV_BLUETOOTH="${MEETINGS_DEV_BLUETOOTH:-Headphones}"

_connected() {  # _connected input|output "Device Name"
  SwitchAudioSource -a -t "$1" 2>/dev/null | grep -qxF "$2"
}

# Resolve each choice to a physical device name (auto = first connected by priority).
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

_output_device() {
  case "$OUTPUT_SOURCE" in
    jabra)     printf '%s' "$DEV_JABRA" ;;
    bluetooth) printf '%s' "$DEV_BLUETOOTH" ;;
    builtin)   printf '%s' "$DEV_BUILTIN_OUT" ;;
    *)  # auto: Jabra -> Bluetooth -> Built-in
        if   _connected output "$DEV_JABRA";     then printf '%s' "$DEV_JABRA"
        elif _connected output "$DEV_BLUETOOTH"; then printf '%s' "$DEV_BLUETOOTH"
        else printf '%s' "$DEV_BUILTIN_OUT"; fi ;;   # built-in is always present
  esac
}

# Explicit device names (advanced) win over the choices above.
CAPTURE_DEVICE="${MEETINGS_CAPTURE_DEVICE:-Input Capture ($(_input_device))}"
OUTPUT_DEVICE="${MEETINGS_OUTPUT_DEVICE:-Output Capture ($(_output_device))}"

# --- Internal: venv + state live OUTSIDE the (re-importable) workflow bundle -
SUPPORT="${alfred_workflow_data:-$HOME/Library/Application Support/AlfredMeetings}"
VENV="$SUPPORT/venv"
PY="$VENV/bin/python3"
