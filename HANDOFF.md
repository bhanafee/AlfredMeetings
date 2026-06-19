# Handoff — AlfredMeetings

/ Status as of 2026-06-18. Recording now works **inside Alfred** (the hard part — a
macOS TCC/microphone fight, see below), and `rec` now **auto-transcribes** on stop.
Scripts all verified; the auto-transcribe chain + `notes` still want one run through
the Alfred GUI. /

## What this project is
An Alfred 5 workflow (repo = source of truth, packaged via `./build.sh`) with three
components: `rec` (toggle stereo recording), `transcribe` (stereo → speaker-labeled
Markdown), `notes` (transcript → minutes/summary/clean/custom via local Ollama). Full
design + usage in `README.md`. All processing is local. **`rec` now auto-transcribes:
stopping a recording produces the transcript automatically (commit `f0e1c19`); the
`transcribe` keyword remains for manual/re-runs. `notes` is still run manually.**

## Done and verified
- **`rec`** (component 1) — built and verified live across **all three device paths**
  (Jabra USB, built-in mic+speakers, Bluetooth headset): start/stop, output
  switch + restore, channel layout (c0 = mic → Me/left, c1+c2 = BlackHole → Them/right;
  pan filter unchanged), and clean stereo split confirmed each time. **Verified running
  from the Alfred GUI** (commit `5479f3e`) after solving the microphone-TCC problem
  below — a real recording lands in `~/Desktop/Meeting Notes/` with the mic on Me.
- **`transcribe`** (component 2) — built, e2e verified. Independent per-channel Whisper
  passes → `Me`/`Them` labels → chronological merge. **No-speech gate added** (commit
  `4f61d38`): Whisper hallucinates confident filler ("Thank you.") on a *silent*
  channel with a low `no_speech_prob`, so it gates on **audio energy** instead — drops
  segments whose RMS < `--silence-dbfs` (default −50). Verified silent segments sit at
  −55…−240 dBFS vs real speech at −17…−35 dBFS, so it never eats real (even quiet)
  speech. Model `whisper-large-v3-turbo` downloaded + cached.
- **`notes`** (component 3) — built, e2e tested against local Ollama `qwen3:4b-instruct`
  for clean/summary/minutes/custom. Action items correctly attributed to speakers.
- **Full `rec → transcribe → notes` chain** — verified on live recordings; speaker
  attribution correct in the minutes; no phantom lines on silent channels.
- **Audio device selection** — Alfred exposes **two independent dropdowns**:
  *Microphone (input)* `MEETINGS_INPUT_SOURCE` and *Listening device (output)*
  `MEETINGS_OUTPUT_SOURCE`, each `jabra|builtin|bluetooth|auto`. **Auto** (default)
  picks the first *connected* device by priority (input: Jabra→Built-in→Bluetooth;
  output: Jabra→Bluetooth→Built-in) via `SwitchAudioSource`. Each choice maps to a
  device named by the convention **`Input Capture (<device>)`** / **`Output Capture
  (<device>)`** where the parenthesized part is the exact device name. Resolution
  verified for every choice + auto + advanced overrides.
- **`info.plist`** — real Alfred 5 schema, `plutil -lint` clean; wires the three
  keywords → scripts → notifications and exposes all config (the two dropdowns, output
  folder, models, advanced device overrides) in the Configure Workflow panel.
- **Packaged**: `dist/AlfredMeetings.alfredworkflow` built and bundle-verified.

## Audio setup on this machine (all built in Audio MIDI Setup, BlackHole installed)
Six devices exist, one aggregate-input + one multi-output per source:
- `Input Capture (Jabra Engage 75)` / `Output Capture (Jabra Engage 75)`
- `Input Capture (MacBook Air Microphone)` / `Output Capture (MacBook Air Speakers)`
- `Input Capture (Headphones)` / `Output Capture (Headphones)`   (Bluetooth)

Each aggregate = that mic **first** + BlackHole 2ch; each multi-output = that device +
BlackHole 2ch. See `setup/audio-setup.md`.

## Microphone under Alfred — the TCC fix (READ THIS before touching recording)
macOS aborts (SIGABRT, `Termination Namespace TCC`) any process that opens the mic
unless its **responsible process** declares `NSMicrophoneUsageDescription`. Alfred
disclaims responsibility for the processes it spawns **and** has no mic usage string,
so bare Homebrew `ffmpeg` becomes the responsible process, has no usage description,
and is killed *before any permission prompt* — the symptom was: `rec` produced no
file, no prompt, empty `ffmpeg.log`, and an `ffmpeg-*.ips` crash report. (Diagnosed
from that crash report; `tccutil`/restarting Alfred/foreground probes all failed
because Alfred can never be the responsible app for the mic.)

**Fix (commit `5479f3e`):** `setup/install.sh` builds an ad-hoc-signed
`~/Library/Application Support/AlfredMeetings/MicCapture.app` = a *copy of ffmpeg* as
the bundle exec + an `Info.plist` carrying `NSMicrophoneUsageDescription` (and
`LSUIElement` so it doesn't steal focus). `record.sh` launches it with
`open -n -a "$MIC_APP" --args …`, so LaunchServices makes **the app its own
responsible process** → its usage description applies → macOS prompts normally
("AlfredMeetings Mic Capture"). Because `open` detaches the process, start/stop find
it by the unique `rec_<stamp>.m4a` filename in its argv (`pgrep`/`pkill -INT`), not a
pid. If the app is rebuilt/re-signed its cdhash changes → the mic grant must be
re-approved once.

## Environment already set up
- Homebrew (under the user's *install* account — the everyday account CANNOT brew
  install; always ask the user to run brew commands): `ffmpeg`, `switchaudio-osx`,
  `ollama` (cask), `blackhole-2ch` (cask) all installed.
- Ollama serving `qwen3:4b-instruct` on :11434.
- Python venv at `~/Library/Application Support/AlfredMeetings/venv` with
  `mlx-whisper` + `openai` + `numpy` (numpy used by the energy gate).
- `MicCapture.app` built in the same support dir by `setup/install.sh` (see above).
  `SUPPORT` is pinned to that fixed path (NOT `$alfred_workflow_data`) in `config.sh`
  + `install.sh`, so the venv and wrapper resolve the same whether you or Alfred runs
  the scripts.

## New in this pass (CLI + indicator + Them speakers) — built, NOT yet live-verified
Three additions, all code-complete and syntax/compile/lint-checked, but none exercised
end-to-end on hardware yet (needs a live take + a fresh `install.sh`):
- **Standalone `meetings` CLI** (`src/bin/meetings`, extensionless): one dispatcher →
  `meetings rec | transcribe [file] | notes <minutes|summary|clean|custom "…"> [file]`.
  Resolves its own path through symlinks, then calls the same `bin/*.sh` Alfred runs.
  `install.sh` symlinks it into `~/.local/bin` (already on PATH). `build.sh` now also
  `chmod +x`'s it. The Alfred-only `notes_filter/notes_run` are untouched.
- **Menu-bar recording indicator** (`src/indicator/RecIndicator.swift`): a native
  `NSStatusBar` accessory app (LSUIElement, no Dock icon) showing a blinking red ●
  with a "Stop recording" item. `record.sh` launches it via `open -n -a … --args
  --stamp <stamp> --stop <record.sh>` after a confirmed start, and kills it on stop via
  `pkill -f "RecIndicator.app.*$stamp"` (stamp = audio basename minus `rec_`/`.m4a`).
  Built + ad-hoc-signed by `install.sh` exactly like `MicCapture.app` (swiftc verified
  present at `/usr/bin/swiftc`; compiles clean). `INDICATOR_APP` added to `config.sh`;
  guarded so a missing app never blocks recording.
- **Per-speaker Them labels** (`pyannote.audio` 4.0.4): `transcribe.py` runs diarization
  on the **right channel only** and maps each silence-gated Whisper segment to the
  max-overlap speaker → `Them 1`, `Them 2`, … (Me unchanged). New helpers
  `diarize_turns` / `speaker_for` / `label_right_segments`; `transcribe_channel` now
  returns `(start,end,text)` and the caller applies labels. **Graceful fallback**: no
  pyannote/torch, no HF credential, gated-model denial, or any runtime error → logs a
  warning and keeps the single `"Them"` label (transcribe never hard-fails). `DIARIZE`/
  `HF_TOKEN`/`DIARIZE_MODEL` in `config.sh`, passed via `transcribe.sh`; Alfred config
  fields (Speaker labels popup + HF token) in `info.plist` (plutil clean). `install.sh`
  now also `pip install pyannote.audio`.
  - **pyannote 4.x gotchas (all handled — see commits a7ced63, f7a109e, 4806926):**
    (1) auth kwarg is `token=`, not `use_auth_token=`; (2) the real gated repo is
    **`pyannote/speaker-diarization-community-1`** (4.x flagship) — even loading the old
    `speaker-diarization-3.1` id pulls community-1's PLDA, so that is the repo to accept
    (NOT segmentation-3.0 / diarization-3.1). We default to community-1, overridable via
    `MEETINGS_DIARIZE_MODEL`. (3) The pipeline returns a `DiarizeOutput`, not an
    `Annotation`; we read `.exclusive_speaker_diarization` (non-overlapping, built for
    transcription) and fall back to `.speaker_diarization` / a legacy `Annotation`.
    (4) Credential: `MEETINGS_HF_TOKEN` if set, else `huggingface_hub.get_token()`
    (cached `hf auth login` / `HF_TOKEN` env) — the user authed via a cached login, no
    env var.
  - **Verified live (plumbing):** `meetings transcribe` on `rec_2026-06-18_15-42-37.m4a`
    ran clean via the symlinked CLI; `diarize_turns` with an empty token resolved the
    cached login, loaded community-1, ran, and extracted a speaker turn. That clip is a
    **solo (Me-only)** take, so 2-speaker `Them 1/2` output is the one thing still
    needing a real multi-remote-speaker take (mapping logic itself unit-tested).

To finish: a live `meetings rec` for the menu-bar ● (announce devices first), and a
two-remote-speaker take to see `Them 1/2`. Repackage already done (`./build.sh`); still
need reimport + restart Alfred so the new info.plist config fields load. Branch:
`feature/cli-indicator-them-speakers` (not merged).

## Remaining work
- **`rec` from Alfred:** ✅ done (prompt → Allow once → records; verified).
- **Auto-transcribe chain (`rec` stop → transcript):** wired + logic-verified (guard
  silent on start, stop-path resolves newest → transcript) and Alfred was reloaded so
  the new graph (`002 → 003` + `002 → 012`) is live — but **not yet confirmed by a real
  rec→stop in the Alfred GUI**. Do that: `rec`, speak, `rec` to stop → expect a "Saved"
  notification then a "Transcript ready" notification + a `*.transcript.md` file. (Note:
  transcription runs while Alfred shows the transcribe action "running"; on a long
  meeting that's a minute+.)
- **`notes` from Alfred GUI:** still not run *under Alfred*, only via the script. Uses
  the venv (path fixed by the `SUPPORT` pin) + Ollama. Confirm: `notes` → Minutes lands
  in `~/Desktop/Meeting Notes/` and the notification fires.
- **Installer reproducibility:** the live fixes were synced straight into the installed
  workflow dir and `MicCapture.app` was built by hand during debugging. For a clean
  machine the flow is: `setup/install.sh` (builds venv + `MicCapture.app`) →
  `./build.sh && open dist/AlfredMeetings.alfredworkflow` (import) → first `rec` grants
  the mic prompt. Worth doing once from scratch to confirm `install.sh` alone produces
  a working `MicCapture.app`.
- Keep the repo authoritative: any GUI fix → mirror into `src/` and re-export.

## Conventions / gotchas
- **Device quality**: Bluetooth mic forces SCO → low-quality *listening* for the whole
  call (transcription is fine, Whisper targets 16 kHz). Jabra (USB) does **not** drop
  its output when its mic opens (verified). Speakers-as-output causes acoustic bleed
  (far side → mic → mislabeled as Me) — prefer a headset; `auto` input order already
  avoids the Bluetooth mic when a Jabra/built-in mic is present.
- **Built-in mic level**: if a built-in-mic take transcribes as silence, check
  System Settings → Sound → Input → *MacBook Air Microphone* input volume — low gain
  reads as silence to Whisper (hit this in testing; raising it fixed it).
- **Dev/test helper**: `setup/devtest.sh start <in> <out>` / `stop` toggles `record.sh`
  while forcing a source, giving one stable command prefix. It's pre-approved in
  `.claude/settings.local.json` (gitignored) so live test takes don't prompt.
- Scripts compute `ROOT` from `BASH_SOURCE` and source `config.sh`; Alfred runs them
  with cwd = bundle root, so the `./bin/...` paths in `info.plist` resolve. `config.sh`
  prepends `/opt/homebrew/bin` to PATH so `SwitchAudioSource` resolves during auto.
- **Iterating on the installed workflow:** the installed copy lives at
  `~/Library/Application Support/Alfred/Alfred.alfredpreferences/workflows/user.workflow.*/`.
  Copying changed **scripts** in takes effect immediately (Alfred re-reads them per run);
  changing **`info.plist`** (the graph/config) needs Alfred to reload — restart Alfred
  (`osascript -e 'tell application "Alfred" to quit'` then `open -a "Alfred 5"`) or
  reimport. Always mirror fixes back into `src/` so the repo stays authoritative.
- `config.sh` reads `MEETINGS_*` env vars with `:-` defaults, so empty Alfred config
  values safely fall back.
- Naming contract between steps: recordings `rec_*.m4a`, transcripts
  `*.transcript.md`; `transcribe`/`notes` auto-pick the newest of each when run with
  no argument.
- venv/state live OUTSIDE the bundle (`~/Library/Application Support/AlfredMeetings`)
  so re-importing the workflow doesn't wipe them.
