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

# --- Audio device names (must match what you create in Audio MIDI Setup) ----
# Aggregate INPUT device = built-in mic + BlackHole 2ch
CAPTURE_DEVICE="${MEETINGS_CAPTURE_DEVICE:-Meeting Capture}"
# Multi-OUTPUT device = speakers + BlackHole 2ch (so you still hear the call)
OUTPUT_DEVICE="${MEETINGS_OUTPUT_DEVICE:-Meeting Output}"

# --- Internal: venv + state live OUTSIDE the (re-importable) workflow bundle -
SUPPORT="${alfred_workflow_data:-$HOME/Library/Application Support/AlfredMeetings}"
VENV="$SUPPORT/venv"
PY="$VENV/bin/python3"
