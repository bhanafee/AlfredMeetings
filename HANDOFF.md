# Handoff — AlfredMeetings

> **2026-06-22 (end of session) — WORKING END-TO-END THROUGH THE ALFRED GUI. Resume
> tomorrow with ONE polish task (record.sh first-run prompt timeout), then merge.** Branch
> `feature/coreaudio-tap-capture`, NOT merged. Last 3 commits are this session's fixes
> (`fc96110` silence-start + TCC crash, `2c78ff8` system-audio TCC grant). Working tree
> clean; workflow repackaged (`dist/AlfredMeetings.alfredworkflow`); state clean (no orphan
> procs, no recording.state, volume 19, no stray rec_*.m4a). System-audio grant IS in place
> on this machine (`preflight == 0`).
>
> **What works now (user-verified in the Alfred GUI this session):** `rec` start → stop →
> saved `rec_*.m4a` → auto-transcript with Me/Them. Headless this session also verified the
> two-speaker `Them 1`/`Them 2` diarization split (Daniel/Samantha, 6/6 lines) and that the
> capture starts in SILENCE (rec before anyone talks) with the tap filling Them once audio
> appears.
>
> **THE ONE REMAINING TASK (tomorrow): record.sh first-run prompt timeout.**
> On a CLEAN machine (no grant yet), the first `rec` makes MeetingCapture show the System
> Audio Recording prompt and wait up to 120s for it — but `record.sh` only polls ~10s for
> "recording (start confirmed)" then kills the capture (orphaning the prompt). It's a
> one-time prime (like the mic grant), but the UX is poor. Fix in `src/bin/record.sh` around
> the confirm loop (verified line numbers today):
>   - **L94:** `for _ in $(seq 1 40); do … sleep 0.25` = the ~10s ceiling.
>   - **L95–97:** greps `MeetingCapture.log` for `recording (start confirmed)` / `^(FAIL|FATAL):`.
>   - **L100–103:** on no-confirm it `pkill -INT`s the capture and prints "click Allow … mic prompt".
>   Plan: when the log shows MeetingCapture's line `requesting System Audio Recording
>   permission` (it logs exactly that), EXTEND the ceiling (e.g. to ~125s) so the user can
>   click Allow, and update the failure/echo message to mention **System Audio Recording**
>   (not just the mic). Then on a clean machine: first `rec` prompts → Allow → it records;
>   subsequent runs `preflight == 0`, no wait. Re-test the normal (already-granted) path too
>   so the common case still confirms in ~1s.
>
> **After that:** repackage (`./build.sh`) if record.sh changed, reimport into Alfred, one
> more GUI `rec` to confirm, then MERGE `feature/coreaudio-tap-capture`.
>
> **Key facts for the fix (don't re-derive):**
>   - Capture app runs from `~/Library/Application Support/AlfredMeetings/MeetingCapture.app`
>     (path pinned in config.sh), NOT the workflow bundle — so rebuilding it via install.sh's
>     block takes effect for Alfred immediately (no reimport needed for app-only changes).
>   - Rebuilding the app changes its cdhash → TCC re-confirms the existing grant WITHOUT a
>     visible prompt (observed: preflight=2 → request → "GRANTED" instantly). So routine
>     rebuilds don't re-prompt; only a never-granted machine does.
>   - `ensureSystemAudioCaptureAuthorized()` in MeetingCapture.swift gates the tap; the
>     three required pieces (Info.plist `NSAudioCaptureUsageDescription`, private
>     `TCCAccessRequest("kTCCServiceAudioCapture")`, active NSApplication) are all in place.
>   - `kAudioAggregateDeviceTapAutoStartKey` MUST stay `false` (true => no start in silence).
>
> <details><summary>Earlier same-session detail: the system-audio TCC root cause (still true)</summary>
>
> **2026-06-22 — RESOLVED: the real bug was a missing macOS-26/27
> system-audio TCC grant.** The whole "no IOProc callback / Them
> is silent" saga was never coreaudiod corruption or a tap-code defect — it was the
> system-audio-capture permission. On macOS 14.4+ (this machine is **macOS 27.0**, build
> 26A5353q) a Core Audio process tap is gated by the **`kTCCServiceAudioCapture`** TCC
> service, SEPARATE from Microphone, and an unauthorized tap delivers **silence (zeros),
> not an error** — so `AudioDeviceStart` returns 0, the IOProc fires only when there's
> audio to clock it, and the "Them" channel is dead air (`-inf`).
>
> **Three things were needed (all now in `src/capture/MeetingCapture.swift` + `install.sh`):**
> 1. **Info.plist key `NSAudioCaptureUsageDescription`** (NOT `NSSystemAudioCaptureUsage…`
>    — that wrong name was tried first and TCC silently refused to prompt with no purpose
>    string). The bundle keeps `NSMicrophoneUsageDescription` too (mic sub-device).
> 2. **Explicit `TCCAccessRequest("kTCCServiceAudioCapture")`** via the private TCC
>    framework (dlopen `…/TCC.framework/Versions/A/TCC`, `TCCAccessPreflight` +
>    `TCCAccessRequest`) — declaring the key alone never auto-prompts for this service
>    (unlike Microphone, which coreaudiod prompts for). Modeled on insidegui/AudioCap.
> 3. **An active `NSApplication`** (`.accessory` policy + `activate`) BEFORE the request —
>    the prompt is presented by OUR process, and a bare CoreAudio CLI with no WindowServer
>    connection makes `TCCAccessRequest` hang with no UI. `ensureSystemAudioCaptureAuthorized()`
>    does preflight → (if not granted) spin up NSApp → request → pump the run loop ≤120s.
>    Graceful: any failure logs a warning and proceeds (Them just stays silent).
>
> **Verified end-to-end (headless, this session):** rendered a 31s gap-free two-voice
> conversation (Daniel + Samantha) to one WAV, played it through the speakers, captured via
> the production `open` path. Tap captured cleanly (`Them -3.2 dBFS`) and `meetings
> transcribe` produced a **correct `Them 1`/`Them 2` split** (Them 1 = Daniel, Them 2 =
> Samantha, 6/6 lines). A muted run (output volume 0) proved the tap reads the **digital
> stream before output volume** — `Them` still −3.2 dBFS, and the quiet mic bleed fell
> under the −50 dBFS energy gate so the transcript was Them-only with NO `Me` duplicates.
> (At volume 6 the sensitive built-in mic bled enough to duplicate every line on `Me` — a
> speakers+built-in-mic artifact, not a bug; a headset removes it.)
>
> **First-run priming (document for clean installs):** the very first `rec` on a machine
> will show the System Audio Recording prompt and the app waits up to 120s for it.
> `record.sh` only polls ~10s for "start confirmed", so the first run is a one-time prime
> (like the mic grant) — grant it, then `rec` again. Once granted, `preflight == 0` and
> there's no wait. Consider raising record.sh's confirm ceiling for the first run (TODO).
>
> **Still TODO:** repackage (`./build.sh`) + reimport so Alfred's bundle carries the new
> capture app; a real call through the Alfred GUI; then merge. coreaudiod note below about
> "killall after BlackHole removal / reboot" stands but was a RED HERRING for this bug —
> the failures were the missing grant + capturing in silence, not a wedge.
>
> </details>
>
> ---
>
> **2026-06-22 (late) — superseded: the two-speaker headless test (now done, see above).**
> Branch `feature/coreaudio-tap-capture`, NOT merged. Working tree clean, all work committed
> (HEAD = the "killall unreliable after driver removal" doc commit).
>
> **Why a reboot was needed:** BlackHole was fully uninstalled this session (driver, cask,
> and all custom `Input/Output Capture` Audio MIDI Setup devices — user confirmed nothing
> else used it). That HAL driver removal wedged `coreaudiod`: capture FAILs with "no IOProc
> callback". `sudo killall coreaudiod` proved UNRELIABLE here (one cycle, then zero) — a
> reboot is the fix. **This account is unprivileged: the user runs all `sudo`/reboot
> themselves; Claude cannot sudo in-session** (see memory `no-in-session-sudo`).
>
> **First thing post-reboot:** verify capture works with a quick `bash setup/devtest.sh
> start builtin` → expect `recording (start confirmed)` in
> `~/Library/Application Support/AlfredMeetings/MeetingCapture.log` → `bash setup/devtest.sh
> stop`. (Mic already granted; no prompt expected. If it still FAILs, the wedge survived —
> reboot again or investigate.)
>
> **Then run the two-speaker test (the one remaining unverified feature: Me/Them split +
> `Them 1`/`Them 2` diarization).** Prereqs already verified this session: pyannote 4.0.4
> installed, HF token cached (`get_token()` returns one), `DIARIZE=auto`, voices `Daniel`
> (en_GB) + `Samantha` (en_US) present. Approach (do it in ONE shot to spend a single capture
> cycle): set output volume low (`osascript -e 'set volume output volume 6'`) so the mic gets
> minimal bleed while the process tap still captures the full *digital* system-audio mix as
> "Them"; `devtest.sh start builtin`; confirm start; play ~6 alternating `say -v Daniel …` /
> `say -v Samantha …` turns through the speakers; `devtest.sh stop`; restore volume to **19**.
> Then `meetings transcribe <newest rec_*.m4a>` and check the transcript: far-side lines
> should be labeled `Them 1` / `Them 2` (Me = mic/bleed). The exact 6-line conversation script
> is in the session history; any distinct two-voice content works.
>
> **State for the reboot:** output volume restored to 19; no orphan `MeetingCapture`/
> `RecIndicator` procs; no `recording.state`. Session test recordings were cleaned; the
> `~/Desktop/Meeting Notes/rec_*.m4a` that remain predate today.
>
> ---
>
> **2026-06-22 (post-reboot) — RESOLVED: the tap stall was transient `coreaudiod`
> corruption, and the menu-bar indicator leak is fixed. Branch
> `feature/coreaudio-tap-capture`, still NOT merged.**
>
> **Tap stall → resolved.** After the reboot + a clean `setup/install.sh` rebuild, the
> Core Audio process tap confirms its start on the *first* IOProc attempt (no retries)
> and records valid stereo m4a — Me on the mic (left), Them on the tap (right). The
> "ZERO IOProc callbacks" failure documented below was transient `coreaudiod` corruption
> from the many create/destroy cycles during debugging, not a defect in the tap. The
> diagnostic stash (`--no-tap` etc.) was dropped; the committed source is the working one.
>
> **Menu-bar indicator leak → fixed (`src/bin/record.sh`).** Root cause: `record.sh`
> confirmed start by *process existence* (a ~3.6s wait), but `MeetingCapture` spends up to
> 4.5s in its `startConfirmed()` retry loop before it logs `recording (start confirmed)`
> or `FAIL`. So the indicator was launched *before* confirmation; on a failed start it was
> orphaned, and the next `rec` took the start branch (process already gone) without killing
> it → indicators accumulated in the menu bar. Fix: start now (1) truncates the per-run
> capture log and polls it for the real `recording (start confirmed)` marker before
> launching the indicator (bails on `FAIL`/`FATAL` or a 10s ceiling), (2) `pkill`s any
> surviving `RecIndicator.app` on the start path (none should exist when idle), and
> (3) stops a hung capture + clears state on a failed start. Verified end-to-end:
> start → exactly one indicator + one capture → stop → finalized m4a, all procs/state cleared.
>
> **Still unverified:** a real two-speaker take (far-side audio) for the Me/Them split and
> `Them 1/2` diarization — needs a live call or a two-voice clip played through system audio.
>
> <details><summary>Original (now-superseded) reboot finding — kept for history</summary>
>
> **Critical finding (isolated with a diagnostic build):** the Core Audio process tap
> does not deliver IOProc callbacks, so `MeetingCapture` never starts recording. Proven
> by an isolation test (`--no-tap`):
> - **Mic-only aggregate** → WORKS: `AudioDeviceStart` OSStatus 0, IOProc fires, recorded
>   20.1s, Me −11.0 dBFS, mic attaches as sub-device (id 99).
> - **Mic + global process tap** → STALLS: tap creates OK (id 151), mic attaches,
>   `AudioDeviceStart` returns OSStatus 0, but **ZERO IOProc callbacks for a full 10s** →
>   `FAIL: capture never started`.
> - Conclusion: the defect is the **process tap in the aggregate's `kAudioAggregateDeviceTapListKey`**
>   wedging the device. It is **NOT** a permission or timing issue — the mic grant, the
>   mic-clocked aggregate, the IOProc, and the AAC m4a writer are all proven working.
>   (Every "no IOProc callback" failure earlier in the session was this same tap stall.)
>
> **State at handoff (clean slate, pre-reboot):**
> - Removed `MeetingCapture.app`, `RecIndicator.app`, `MicCapture.app` from
>   `~/Library/Application Support/AlfredMeetings/`. **`venv` kept** (unrelated to the bug;
>   rebuilding re-downloads GBs).
> - TCC mic grants: apps deleted, so `tccutil reset <id>` returns "no such bundle id"; the
>   stale Microphone entries (MeetingCapture / MicCapture / MicTapMerge) **flush on reboot**.
> - **Diagnostic source edits are STASHED** — `git stash` entry *"diagnostic capture edits
>   (--no-tap, 10s window, extra logging)"*. Working tree = committed branch source (verified,
>   no `--no-tap`). The harness adds to `MeetingCapture.swift`: a `--no-tap` flag (mic-only
>   aggregate), a single 10s start window (vs committed 3×1.5s) with per-second
>   "waiting for callback" logging, `AudioDeviceStart` OSStatus logging instead of `fail()`,
>   and a log of the aggregate's active sub-device list.
> - Cleared all logs, `recording.state`, and `diag_*.m4a`.
> - `.claude/settings.local.json` (gitignored) gained allow-rules this session: relative
>   `bash setup/devtest.sh`, `transcribe.sh`, `ffprobe`/`ffmpeg`, `pgrep`/`cat`/`tail`/`ls`/`stat`.
>
> **macOS gotcha discovered:** re-signing an ad-hoc app **in place** (`swiftc` over an
> existing bundle + `codesign --force`) made macOS treat it as *damaged* and **delete the
> `.app` on next `open`**. Always rebuild the bundle **from scratch** (`rm -rf` → `mkdir` →
> compile → write Info.plist → `codesign`), exactly as `setup/install.sh` does. Env: macOS
> Darwin 27.0.0; `swiftc` at `/usr/bin/swiftc`; Ollama up; auto-mic = `MacBook Air Microphone`
> (no Jabra/Bluetooth connected).
>
> **POST-REBOOT PLAN:**
> 1. **Clean build:** run `setup/install.sh` (rebuilds + signs `MeetingCapture.app` and
>    `RecIndicator.app` from committed source; venv present so pip steps are fast).
> 2. **Test capture:** `bash setup/devtest.sh start builtin` → expect a macOS mic prompt for
>    "AlfredMeetings Capture" → **Allow**. The committed start window is only 4.5s (3×1.5s),
>    shorter than a prompt response, so the first run primes the grant — then run it again.
>    Check `~/Library/Application Support/AlfredMeetings/MeetingCapture.log`.
> 3. **Branch:**
>    - **If capture now works** → the tap stall was transient `coreaudiod` corruption from
>      our many create/destroy cycles; proceed with the original live verification (record a
>      two-speaker take → stop → transcribe Me/Them → optional Alfred GUI run).
>    - **If the tap still stalls** → genuine defect. Restore the harness (`git stash pop`),
>      rebuild from scratch, and investigate WHY the tap wedges the aggregate. Candidates:
>      (a) the global tap needs a separate start / its own permission on macOS 26;
>      (b) `kAudioAggregateDeviceTapAutoStartKey` + per-tap drift compensation interaction;
>      (c) try a per-PID tap (`--pid`) instead of the global tap;
>      (d) inspect Console/`log stream` for `coreaudiod` errors during the stall.
>      **Diff the committed `MeetingCapture.swift` against the proven-working spike** on
>      branch `spike/system-audio-tap` (`src/spike/`) to find what diverged and broke the tap.
>
> </details>
>
> ---
>
> **2026-06-22 — BlackHole replaced by a Core Audio process tap (branch
> `feature/coreaudio-tap-capture`, NOT merged; needs live verification).**
> Recording no longer uses BlackHole or Audio MIDI Setup. `record.sh` now launches
> `MeetingCapture.app` (`src/capture/MeetingCapture.swift`) — a mic-clocked process-tap
> recorder that writes mic→left ("Me") / system-audio-tap→right ("Them") straight to
> `rec_*.m4a`, with no output rerouting. Decision: `docs/adr/0001-*.md`; plan/checklist:
> GitHub issues #1/#2; the proving spike: branch `spike/system-audio-tap` (`src/spike/`
> with `build-spike.sh` + README evidence), kept off `main`. **Proven headless:** the tap
> captures real audio with no virtual device, the
> mic clocks the timeline through far-side silence, m4a writing, device selection, and
> start-confirmation. **Still needs a real run through Alfred:** `rec` start→stop on a
> live two-speaker call (first run prompts for *Microphone* — Allow), confirming the
> Me/Them split and that `pkill -INT` finalises a valid m4a. The TCC/`open`
> responsible-process discipline below still applies (same reason, now the capture app).
> Everything from here down predates the migration (BlackHole-era) and is historical
> except the TCC and venv/state notes, which still hold.

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
- **Capture FAILs with "no IOProc callback" → `coreaudiod` is wedged.** Symptom:
  `MeetingCapture.log` shows all 3 start attempts failing with "no IOProc callback in 1.5s"
  → `FAIL: capture never started`, even though the mic is granted and the device exists.
  Cause: the Core Audio daemon got into a bad state — confirmed triggers are tearing down a
  HAL driver (e.g. **uninstalling BlackHole**) and many process-tap create/destroy cycles
  (heavy debugging). It is **not** a permission, mic, or code defect. **Fix:**
  `sudo killall coreaudiod` for the *churn* case clears it. **But after a HAL driver removal
  (uninstalling BlackHole), `killall` is UNRELIABLE** — observed 2026-06-22: post-uninstall it
  bought one good record/stop cycle, then re-wedged; a second `killall` (daemon confirmed
  restarted, uptime 40s) bought *zero* cycles. **A full reboot is the reliable fix** there
  (post-reboot the tap ran across many cycles). This account is unprivileged, so **ask the
  user to run the `sudo`/reboot** — Claude can't sudo in-session. Prefer reboot after a
  driver uninstall; reserve `killall` for the create/destroy-churn case.
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
