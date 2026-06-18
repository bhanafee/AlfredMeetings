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
- **`rec`** (component 1) — **written but NOT yet tested** (needs BlackHole live).
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

## Remaining work (post-reboot)
1. **Reboot done** → confirm BlackHole appears: `SwitchAudioSource -a | grep -i blackhole`.
2. **Create audio devices** per `setup/audio-setup.md`:
   - Aggregate input `Meeting Capture` = Built-in Mic (FIRST) + BlackHole 2ch.
   - Multi-output `Meeting Output` = Speakers + BlackHole 2ch.
   Verify: `SwitchAudioSource -a` lists both.
3. **VERIFY THE CHANNEL LAYOUT** — this is the one untested assumption.
   `src/bin/record.sh` assumes the aggregate presents channels as: c0 = mic,
   c1/c2 = BlackHole L/R, and pans `c0=c0 | c1=0.5*c1+0.5*c2`. Confirm the real
   layout before trusting it:
   ```sh
   ffmpeg -f avfoundation -i ":Meeting Capture" -t 1 -y /tmp/probe.m4a   # prints channel count/layout
   ```
   Record a short clip where you talk AND play audio, then check that left=you,
   right=system:
   ```sh
   ffmpeg -i <clip>.m4a -af "pan=mono|c0=c0" -ar 16000 /tmp/L.wav   # should be your voice
   ffmpeg -i <clip>.m4a -af "pan=mono|c0=c1" -ar 16000 /tmp/R.wav   # should be the other side
   ```
   Adjust the pan filter in `record.sh` if the layout differs.
4. **Install & smoke-test the workflow**: `./build.sh && open dist/AlfredMeetings.alfredworkflow`,
   then in Alfred: `rec` (grant ffmpeg mic permission on first run) → speak + play a
   clip → `rec` again to stop → `transcribe` → `notes` → pick Minutes. Confirm files
   land in `~/Desktop/Meeting Notes/` and notifications fire.
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
