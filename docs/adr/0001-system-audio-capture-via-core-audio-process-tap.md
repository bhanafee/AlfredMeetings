# 1. Capture far-side audio with a Core Audio process tap, not BlackHole

Date: 2026-06-22

## Status

Accepted — implemented on branch `feature/coreaudio-tap-capture` (commit adds
`src/capture/MeetingCapture.swift` + rewires `record.sh`/`config.sh`/`install.sh`/
`info.plist`), pending live end-to-end verification through Alfred. Supersedes the
original BlackHole-based capture. Implementation tracked in [issue #2]; motivation in
[issue #1].

## Context

The recorder captures a meeting as stereo with **left = microphone ("Me")** and
**right = far-side / system audio ("Them")**; this channel-as-speaker split is what lets
`transcribe.py` label speakers without diarizing the Me/Them boundary.

To get the far side onto a capturable input, the workflow currently routes system audio
through **BlackHole 2ch** into six hand-built devices in Audio MIDI Setup (an
aggregate-input + a multi-output per source), and `record.sh` switches the system output
device to the multi-output on start and restores it on stop.

This has three structural problems:

1. **Unscriptable setup.** The six devices are built by hand in Audio MIDI Setup and do not
   survive a clean machine — the single biggest barrier to reproducible install ([issue #1];
   HANDOFF flags "installer reproducibility" as unfinished).
2. **All-system capture.** Everything playing — notifications, music, other apps — bleeds
   into "Them"; there is no way to scope capture to the call application.
3. **Output reroute state.** Switching/restoring the system output adds a failure mode
   (a crash leaves the wrong output device selected), and multi-output devices lose hardware
   volume control and can drift sample rates between sub-devices.

macOS 14.4+ provides a first-party **Core Audio process-tap API**
(`CATapDescription` + `AudioHardwareCreateProcessTap`) that captures system or per-app audio
**without any virtual device**. The project already builds and ad-hoc-signs small native
helpers (`MicCapture.app`, `RecIndicator.swift`), so a Swift capture helper is within the
existing toolchain.

A throwaway spike (branch `spike/system-audio-tap`) validated the approach end-to-end on
macOS 27.0 / build 26A:

- A process tap captures system audio with **no virtual device** (real audio, peak −18 dBFS).
- A single private aggregate device of **{ mic as clock master + tap }** delivers both
  streams to one IOProc, sample-aligned, written as mic→left / tap→right.
- **The mic clocks the timeline continuously even when the far side is silent** — the key
  risk, since a tap-*only* aggregate clocks only while the tapped source renders. Silent-far-
  side take: full duration, left −47 dB (mic), right −inf. The silent right channel sits
  below `transcribe.py`'s −50 dBFS energy gate, so no phantom "Them" segments.
- Device selection by UID / name and start-confirmation (retry, else fail) both work.

## Decision

Capture the far side with a **Core Audio process tap clocked by the real microphone**,
inside a single private aggregate device, and **retire BlackHole and the Audio MIDI Setup
aggregates**.

A native helper (`MeetingCapture.app`, replacing `MicCapture.app`) will:
- resolve the mic by UID/name (driven by `MEETINGS_INPUT_SOURCE`),
- create a process tap — global, or scoped to the call app via `--pid`,
- build an aggregate `{ mainSubDevice: mic, tapList: [tap] }`,
- run one IOProc writing **mic → left, tap mono-mix → right**, and
- confirm start, then finalise an `.m4a` matching the existing `rec_*.m4a` contract.

The Me/Them channel convention, `transcribe.py`, `notes`, and the auto-transcribe chain are
unchanged. BlackHole stays available and documented as a fallback until the tap path is
verified on all three input device paths.

## Alternatives considered

- **Keep BlackHole.** Rejected: the manual six-device setup is the project's core fragility
  ([issue #1]) and cannot scope capture to the call app. Acceptable only as a fallback.
- **ScreenCaptureKit audio.** Also virtual-device-free and supports per-app audio, but is
  oriented around screen/window capture and a heavier API surface for an audio-only need;
  process taps map more directly onto the existing aggregate/IOProc model.
- **Acoustic capture (speakers → mic).** Rejected outright: bleed mislabels the far side as
  "Me" (already a documented hazard); a headset is the existing mitigation.

## Consequences

**Positive**
- No Audio MIDI Setup and no BlackHole → scriptable, reproducible install.
- Optional per-app scoping (`--pid`) eliminates notification/music bleed.
- No output reroute: the user keeps their normal output device and volume; one failure mode
  and the output switch/restore bookkeeping are removed from `record.sh`.
- Stays within the existing native-helper toolchain; pipeline downstream is untouched.

**Negative / costs**
- New native code to maintain (the capture helper) and a higher **macOS floor (14.4+)**.
- Same TCC discipline as the mic: the tap is gated by the **Microphone** service, so the
  helper needs `NSMicrophoneUsageDescription` and must be launched via `open` to be its own
  responsible process (bare-binary launch yields silent zeros).
- Must confirm IOProc start before trusting a take — a tap-only aggregate won't clock, and
  device churn can race the start (mitigated by mic-as-clock + start-confirmation/retry).
- Open items to resolve during implementation: `.m4a` finalisation on SIGINT, reliable
  call-app pid selection, and re-verifying clocking with a USB (Jabra) and Bluetooth mic as
  the aggregate clock master.

## References

- Spike: branch `spike/system-audio-tap` (`src/spike/SystemAudioTap.swift`,
  `MicTapMerge.swift`, `README.md` with the evidence tables) — kept on that branch, not
  merged to `main`.
- [issue #1] Re-evaluate selection of BlackHole.
- [issue #2] Replace BlackHole with a Core Audio process tap for Them-side capture
  (implementation plan + checklist).

[issue #1]: https://github.com/bhanafee/AlfredMeetings/issues/1
[issue #2]: https://github.com/bhanafee/AlfredMeetings/issues/2
