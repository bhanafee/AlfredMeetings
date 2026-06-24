# Audio setup

**There is nothing to set up.** As of [ADR 0001](../docs/adr/0001-system-audio-capture-via-core-audio-process-tap.md),
AlfredMeetings captures the far side of a call with a **Core Audio process tap** instead
of BlackHole + hand-built Audio MIDI Setup devices.

The recorder builds a private aggregate device on the fly:

- your **microphone** is the clock master and lands on the **left** channel ("Me"),
- a **process tap** of system audio lands on the **right** channel ("Them").

Your normal output device and volume are untouched — nothing is rerouted.

## Permission

The tap is gated by the macOS **Microphone** privacy service. The first time you run
`rec`, macOS prompts for microphone access for **"AlfredMeetings Capture"** — click
**Allow**. (If you rebuild the capture app, its code signature changes and macOS asks
again, once.) The app must be launched via `open` — which `record.sh` does — so it is its
own responsible process and the prompt is attributed to it.

## Choosing the mic

The **Microphone (input)** popup in Alfred's *Configure Workflow* panel picks your voice
input (`auto` = first connected of Jabra → Built-in → Bluetooth). Advanced: set
`MEETINGS_MIC_DEVICE` to a CoreAudio UID or a name substring. To list device names/UIDs:

```
"$HOME/Library/Application Support/AlfredMeetings/MeetingCapture.app/Contents/MacOS/MeetingCapture" --list
```

## Capturing only the meeting app

Leave **Meeting app (Them)** blank to capture all system audio, or set it (or
`MEETINGS_THEM_APP`) to the meeting app's process name (e.g. `zoom.us`,
`Microsoft Teams`) to tap only that app — no notification/music bleed.

## Requirements

- macOS 14.4 or newer (the process-tap API).
- Xcode Command Line Tools (`swiftc`) so `setup/install.sh` can build the capture app.

## Legacy: removing BlackHole

Earlier versions routed audio through **BlackHole** plus six hand-built devices in Audio
MIDI Setup — one `Input Capture (<device>)` aggregate and one `Output Capture (<device>)`
multi-output per source (Jabra / Built-in / Bluetooth). **None of that is used anymore**;
the process tap replaced all of it, and nothing in the current code references those
devices, the BlackHole driver, or any output rerouting. Existing recordings are unaffected.

Removing it is optional cleanup. Two independent steps, safest order:

1. **Delete the custom devices (zero risk, reversible).** Open **Audio MIDI Setup**, and in
   the left-hand device list delete every `Input Capture (…)` and `Output Capture (…)`
   entry (select → `-` button, or right-click → *Remove Device*). These were created only
   for the old path; macOS rebuilds nothing on its own, and you can recreate them later
   from this file's git history if ever needed.

2. **Uninstall the BlackHole driver (only if nothing else uses it).** BlackHole is a
   system-wide virtual audio driver — leave it if any other app routes audio through it
   (OBS, screen recording with sound, Loopback, etc.). To remove it, quit audio apps, then
   from the Homebrew **install account** (the everyday account can't `brew uninstall`):

   ```
   brew uninstall --cask blackhole-2ch
   ```

   Reopen Audio MIDI Setup afterward to confirm the `BlackHole 2ch` device is gone.

The old BlackHole-era setup instructions remain in git history if you ever need them.
