# Handoff — AlfredMeetings

/ Status as of 2026-06-18, before the BlackHole-required reboot. /

## What this project is
An Alfred 5 workflow (repo = source of truth, packaged via `./build.sh`) with three
independent components: `rec` (toggle stereo recording), `transcribe` (stereo →
speaker-labeled Markdown), `notes` (transcript → minutes/summary/clean/custom via
local Ollama). Full design + usage in `README.md`. All processing is local.

## Done and verified
- **`notes`** (component 3) — built, e2e tested against local Ollama `qwen3:4b-instruct`
  for clean/summary/minutes/custom. Action items correctly attributed to speakers.
- **`transcribe`** (component 2) — built, e2e tested on a synthesized stereo clip;
  channel split → `Me`/`Them` labels → chronological merge all work. Whisper model
  (`whisper-large-v3-turbo`) is downloaded and cached.
- **`rec`** (component 1) — built and verified (2026-06-18, post-reboot). BlackHole
  live; `Meeting Capture` + `Meeting Output` created. Channel layout CONFIRMED:
  c0 = mic (Me/left), c1+c2 = BlackHole (Them/right) — pan filter in `record.sh` is
  correct, no change needed. Verified start/stop/output-switch/restore, stereo split,
  and the full `rec → transcribe → notes` chain on a live recording.
  **KEY FINDING:** electrical channel separation is perfect, but a *speaker* in
  `Meeting Output` plays the far side aloud and the built-in mic picks it back up,
  bleeding the far side into the Me channel (Whisper transcribes even faint bleed).
  Fix = listen on **headphones**, not speakers. Documented in `setup/audio-setup.md`.
- **`info.plist`** — authored from real Alfred 5 schema, `plutil -lint` clean, wires
  `rec`→script→notification, `transcribe`→script→notification, `notes` scriptfilter→
  script→notification. Exposes config via Configure Workflow panel.
- **Packaged**: `dist/AlfredMeetings.alfredworkflow` built and bundle-verified.

## Environment already set up
- Homebrew (under the user's *install* account — the everyday account CANNOT brew
  install; always ask the user to run brew commands): `ffmpeg`, `switchaudio-osx`,
  `ollama` (cask), `blackhole-2ch` (cask, **reboot pending**) all installed.
- Ollama serving `qwen3:4b-instruct` on :11434.
- Python venv at `~/Library/Application Support/AlfredMeetings/venv` with
  `mlx-whisper` + `openai`.

## Remaining work
Steps 1–3 below are DONE (2026-06-18). Only the live Alfred GUI test (4) remains, plus
the optional headphones device tweak (see `setup/audio-setup.md`).

1. ~~Reboot → confirm BlackHole.~~ ✅ BlackHole live.
2. ~~Create `Meeting Capture` + `Meeting Output`.~~ ✅ both exist.
3. ~~Verify channel layout.~~ ✅ confirmed correct; `record.sh` unchanged.
4. **Install & live-smoke-test in Alfred** (the one thing still needing a human mic):
   `./build.sh && open dist/AlfredMeetings.alfredworkflow`, then in Alfred:
   `rec` (grant ffmpeg mic permission on first run) → **wear headphones**, speak AND
   play a clip → `rec` again to stop → `transcribe` → `notes` → pick Minutes. Confirm
   files land in `~/Desktop/Meeting Notes/`, notifications fire, and your voice lands
   under **Me** with the call under **Them**. (Scripts already verified end-to-end
   outside Alfred; this just exercises the GUI graph + real mic input.)
5. Anything off in the Alfred graph can be fixed in the GUI and re-exported, but keep
   the repo authoritative — mirror fixes back into `src/`.

## Conventions / gotchas
- Scripts compute `ROOT` from `BASH_SOURCE` and source `config.sh`; Alfred runs them
  with cwd = bundle root, so the `./bin/...` paths in `info.plist` resolve.
- `config.sh` reads `MEETINGS_*` env vars with `:-` defaults, so empty Alfred config
  values safely fall back.
- Naming contract between steps: recordings `rec_*.m4a`, transcripts
  `*.transcript.md`; `transcribe`/`notes` auto-pick the newest of each when run with
  no argument.
- venv/state live OUTSIDE the bundle (`~/Library/Application Support/AlfredMeetings`)
  so re-importing the workflow doesn't wipe them.
