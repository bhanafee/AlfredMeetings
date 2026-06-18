# One-time audio setup

To capture **you (mic)** and **everyone you hear (system audio)** on *separate
channels*, AlfredMeetings records from an aggregate input device whose channels
are mic on the left and BlackHole (system audio) on the right.

## 1. Install BlackHole

BlackHole is a virtual audio device that lets us capture system audio. Install it
(under your Homebrew-capable account):

```
brew install --cask blackhole-2ch
```

If BlackHole doesn't appear in Audio MIDI Setup afterwards, restart the Mac once.

## 2. Create two devices in Audio MIDI Setup

Open **Audio MIDI Setup** (Spotlight → "Audio MIDI Setup"). Click the **+** at the
bottom-left.

### a) Aggregate Device — name it exactly `Meeting Capture`
Tick, **in this order**:
1. **Built-in Microphone** (1 channel)
2. **BlackHole 2ch** (2 channels)

This produces a 3-channel input: channel 1 = your mic, channels 2–3 = system audio.
The recorder maps channel 1 → left (**Me**) and channels 2–3 → right (**Them**).

> Order matters: the mic must be the first sub-device so it lands on channel 1.

### b) Multi-Output Device — name it exactly `Meeting Output`
Tick:
1. Your normal speakers/headphones (e.g. **MacBook Air Speakers**)
2. **BlackHole 2ch**

This lets you still *hear* the call while its audio is mirrored into BlackHole for
capture. The recorder switches your output to this device while recording and
restores your previous output device when you stop.

## 3. Verify

```
SwitchAudioSource -a            # should list "Meeting Capture" and "Meeting Output"
```

If you named the devices differently, set `MEETINGS_CAPTURE_DEVICE` /
`MEETINGS_OUTPUT_DEVICE` (see `src/config.sh`) to match.
