# Meeting Notes — Alfred workflow

Record a meeting, transcribe it locally with speaker separation, and turn the
transcript into clean notes / a summary / minutes — all on-device, no cloud, no
per-meeting cost. Built for Apple Silicon.

Three independent components, each an Alfred keyword that also accepts a file so
they chain but can run standalone:

| Keyword | Input | Output |
|---|---|---|
| `rec` | — (toggle; run again to stop) | stereo `.m4a` (left = your mic → **Me**, right = system audio → **Them**) |
| `transcribe [file]` | newest recording, or a file you pass | timestamped, speaker-labeled `.md` transcript |
| `notes` | newest transcript, or a file you pass | processed `.md`: **Minutes**, **Summary**, **Clean up**, or a **Custom** instruction |

Everything is written to `~/Desktop/Meeting Notes/` by default (configurable).

## How it works

- **Recording** captures an aggregate input device (mic + BlackHole) and pans it to
  a stereo file: mic on the left, system audio on the right. While recording, output
  is routed through a multi-output device so you still hear the call; your previous
  output device is restored when you stop.
- **Transcription** splits the stereo file into two mono channels, transcribes each
  independently with [`mlx-whisper`](https://github.com/ml-explore/mlx-examples)
  (`whisper-large-v3-turbo`), and merges the segments chronologically with `Me` /
  `Them` labels. This deterministic two-way split is more reliable than acoustic
  diarization (it won't, however, tell multiple *remote* speakers apart — they share
  the system-audio channel).
- **Notes** sends the transcript to a local Ollama model (`qwen3:4b-instruct` by
  default) via its OpenAI-compatible endpoint, using one of the bundled prompts.

## Setup

### 1. Homebrew packages

```sh
brew install ffmpeg switchaudio-osx
brew install --cask blackhole-2ch        # reboot afterwards
brew install --cask ollama
```

Then start Ollama and pull the model:

```sh
open -a Ollama
ollama pull qwen3:4b-instruct
```

### 2. Python environment

```sh
./setup/install.sh
```

Creates a venv at `~/Library/Application Support/AlfredMeetings/venv` and installs
`mlx-whisper` + `openai`. (No Homebrew needed for this step.)

### 3. Audio devices

Follow [`setup/audio-setup.md`](setup/audio-setup.md) to create the `Meeting Capture`
(aggregate input) and `Meeting Output` (multi-output) devices in Audio MIDI Setup.

### 4. Install the workflow

```sh
./build.sh                      # produces dist/AlfredMeetings.alfredworkflow
open dist/AlfredMeetings.alfredworkflow
```

The first `transcribe` run downloads the Whisper model (~1.5 GB, one time). The
recorder needs microphone permission — macOS will prompt on first use.

## Configuration

Defaults live in [`src/config.sh`](src/config.sh) and every value can be overridden
by an environment variable. The most common ones are also exposed in Alfred's
**Configure Workflow** panel:

| Variable | Default |
|---|---|
| `MEETINGS_OUTPUT_DIR` | `~/Desktop/Meeting Notes` |
| `MEETINGS_LLM_MODEL` | `qwen3:4b-instruct` |
| `MEETINGS_LLM_BASE_URL` | `http://localhost:11434/v1` |
| `MEETINGS_WHISPER_MODEL` | `mlx-community/whisper-large-v3-turbo` |
| `MEETINGS_CAPTURE_DEVICE` | `Meeting Capture` |
| `MEETINGS_OUTPUT_DEVICE` | `Meeting Output` |

On a 24 GB Mac you can point `MEETINGS_LLM_MODEL` at a larger model (e.g.
`qwen2.5:7b`) for higher-quality minutes.

## Repository layout

```
build.sh                 Package src/ into dist/AlfredMeetings.alfredworkflow
setup/install.sh         Build the Python venv
setup/audio-setup.md     One-time audio device guide
src/info.plist           Alfred workflow graph
src/config.sh            Shared, env-overridable configuration
src/bin/                 Component entrypoints (record / transcribe / notes)
src/engine/              Python engines + prompt templates
```
