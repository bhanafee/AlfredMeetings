# Meeting Notes — Alfred workflow

Record a meeting, transcribe it locally with speaker separation, and turn the
transcript into clean notes / a summary / minutes — all on-device, no cloud, no
per-meeting cost. Built for Apple Silicon.

Three independent components, each available **both as an Alfred keyword and as a
`meetings` subcommand in your shell**. Each also accepts a file, so they chain but can
run standalone:

| Keyword | `meetings` command | Input | Output |
|---|---|---|---|
| `rec` | `meetings rec` | — (toggle; run again to stop) | stereo `.m4a` (left = your mic → **Me**, right = system audio → **Them**) |
| `transcribe [file]` | `meetings transcribe [file]` | newest recording, or a file you pass | timestamped, speaker-labeled `.md` transcript |
| `notes` | `meetings notes <mode> [file]` | newest transcript, or a file you pass | processed `.md`: **Minutes**, **Summary**, **Clean up**, or a **Custom** instruction |

Everything is written to `~/Desktop/Meeting Notes/` by default (configurable).

While a recording is active, a red ● appears in the **menu bar** — click it to stop
(handy when the `rec` toggle leaves you unsure whether you started or stopped).

## How it works

- **Recording** captures an aggregate input device (mic + BlackHole) and pans it to
  a stereo file: mic on the left, system audio on the right. While recording, output
  is routed through a multi-output device so you still hear the call; your previous
  output device is restored when you stop.
- **Transcription** splits the stereo file into two mono channels, transcribes each
  independently with [`mlx-whisper`](https://github.com/ml-explore/mlx-examples)
  (`whisper-large-v3-turbo`), and merges the segments chronologically with `Me` /
  `Them` labels. The deterministic two-way split reliably separates **you** from the
  remote side. To tell *individual remote speakers* apart — who all share the one
  system-audio channel — it additionally runs
  [`pyannote.audio`](https://github.com/pyannote/pyannote-audio) diarization on the
  Them channel and labels each speaker `Them 1`, `Them 2`, … (see
  [Speaker attribution](#speaker-attribution-them-side) below).
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
`mlx-whisper` + `openai` + `pyannote.audio`, builds the menu-bar recording indicator,
and symlinks the `meetings` CLI into `~/.local/bin`. (No Homebrew needed for this step.)

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
| `MEETINGS_DIARIZE` | `auto` (`off` to disable Them-side speaker labels) |
| `MEETINGS_HF_TOKEN` | _(empty)_ — Hugging Face token for diarization |

On a 24 GB Mac you can point `MEETINGS_LLM_MODEL` at a larger model (e.g.
`qwen2.5:7b`) for higher-quality minutes.

## Command line

The same three stages run from your shell via the `meetings` command (symlinked into
`~/.local/bin` by `setup/install.sh`):

```sh
meetings rec                              # start; run again (or click the menu-bar ●) to stop
meetings transcribe [audio]              # newest recording, or a file you pass
meetings notes minutes [transcript]      # also: summary | clean
meetings notes custom "List risks and open questions"
```

`rec` auto-transcribes on stop just as it does under Alfred. The CLI and the Alfred
keywords run the **same** scripts and honour the same `MEETINGS_*` configuration.

## Speaker attribution (Them side)

The mic channel is always **you** ("Me"). Everyone you hear shares the single
system-audio channel, so to label them individually the transcriber runs
`pyannote.audio` diarization on that channel and tags each voice `Them 1`, `Them 2`, …
(the labels are plain text — search-and-replace them with real names afterward).

This needs a free Hugging Face token and one-time access to the gated model
(`pyannote/speaker-diarization-community-1`, the pyannote.audio 4.x flagship pipeline):

1. Create a token at <https://huggingface.co/settings/tokens> (a **Read** token).
2. Accept the model terms at
   <https://huggingface.co/pyannote/speaker-diarization-community-1>.
3. Set the token: Alfred → **Configure Workflow → Hugging Face token**, or export
   `MEETINGS_HF_TOKEN` in your shell.

Override the pipeline with `MEETINGS_DIARIZE_MODEL` if you pin a different pyannote
version (e.g. `pyannote/speaker-diarization-3.1` under pyannote.audio 3.x).

If the token, model access, or `pyannote.audio` is missing, transcription **falls back
to a single `Them` label** — nothing breaks, you just lose the per-speaker split. Set
`MEETINGS_DIARIZE=off` (or the **Speaker labels** popup) to skip it entirely.
Diarization adds a CPU pass over the Them channel, so a long meeting takes a few extra
minutes; set `MEETINGS_DIARIZE_DEVICE=mps` to try the GPU.

## Repository layout

```
build.sh                 Package src/ into dist/AlfredMeetings.alfredworkflow
setup/install.sh         Build the venv, indicator app, and `meetings` CLI symlink
setup/audio-setup.md     One-time audio device guide
src/info.plist           Alfred workflow graph
src/config.sh            Shared, env-overridable configuration
src/bin/                 Component entrypoints (record / transcribe / notes)
src/bin/meetings         Single-entrypoint CLI dispatcher for the shell
src/engine/              Python engines + prompt templates
src/indicator/           Native menu-bar "recording now" app (Swift)
```
