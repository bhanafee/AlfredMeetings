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

## 2. Create the devices in Audio MIDI Setup

The **Microphone (input)** and **Listening device (output)** are chosen independently
in Alfred → Configure Workflow. Each can be a specific source or **Auto** (the default),
which picks the first *currently connected* device by priority:

- **Microphone** order: Jabra → Built-in → Bluetooth
- **Listening device** order: Jabra → Bluetooth → Built-in

Each source maps to a device you build once in Audio MIDI Setup, named by an exact
convention: **`Input Capture (<device name>)`** for the aggregate input and
**`Output Capture (<device name>)`** for the multi-output, where `<device name>` is the
*exact* name of the underlying mic/listening device. Build the pairs for whatever
hardware you use (or override the whole name via `MEETINGS_CAPTURE_DEVICE` /
`MEETINGS_OUTPUT_DEVICE`).

| Source | Aggregate INPUT (mic + BlackHole) | Multi-OUTPUT (listen + BlackHole) |
|---|---|---|
| **Jabra** | `Input Capture (Jabra Engage 75)` = Jabra Engage 75 + BlackHole 2ch | `Output Capture (Jabra Engage 75)` = Jabra Engage 75 + BlackHole 2ch |
| **Built-in** | `Input Capture (MacBook Air Microphone)` = MacBook Air Microphone + BlackHole 2ch | `Output Capture (MacBook Air Speakers)` = MacBook Air Speakers + BlackHole 2ch |
| **Bluetooth** | `Input Capture (Headphones)` = Headphones + BlackHole 2ch | `Output Capture (Headphones)` = Headphones + BlackHole 2ch |

Open **Audio MIDI Setup** (Spotlight → "Audio MIDI Setup") and use the **+** at the
bottom-left to add each device. Connect a Bluetooth/USB device first so it's tickable.

### Aggregate inputs
Tick the sub-devices **in this order — the mic must be first** so it lands on channel 1:

1. **the mic** (1 channel) — `Jabra Engage 75`, `MacBook Air Microphone`, or `Headphones`
2. **BlackHole 2ch** (2 channels)

This produces a 3-channel input: channel 1 = your mic, channels 2–3 = system audio.
The recorder maps channel 1 → left (**Me**) and channels 2–3 → right (**Them**). Set
the **Primary**/clock source to the mic and tick **Drift Correction** on BlackHole.

### Multi-outputs
Tick:

1. **the listening device** — `Jabra Engage 75`, `Headphones`, or `MacBook Air Speakers`
2. **BlackHole 2ch**

This lets you still *hear* the call while it's mirrored into BlackHole. The recorder
switches your output to this device while recording and restores your previous output
when you stop. Set the **Primary**/clock source to **BlackHole 2ch** and tick **Drift
Correction** on the listening device.

> ⚠️ **Prefer a headset over speakers.** If your listening device is a *speaker* that
> plays the call out loud, your mic picks the far side back up acoustically and it leaks
> into the **Me** channel — Whisper transcribes even faint bleed, so the far side gets
> mislabeled as you, and the other party hears their own echo. A headset (Jabra,
> Bluetooth) eliminates both (verified: routed only through a headset/BlackHole the mic
> channel sits at the −64 dB noise floor). Use the built-in **speakers** output only for
> solo dictation or a quiet room where you won't talk over the other side.

> 🎧 **Device quality notes.** Using a *Bluetooth* headset's mic forces the link into
> hands-free (SCO) mode, dropping what you hear to low quality for the whole call; pair
> Bluetooth **output** with a different mic (Auto's input order avoids the Bluetooth mic
> when a Jabra or built-in mic is present) to keep listening in hi-fi. The Jabra (USB)
> does **not** degrade its output when its mic is open (verified) — it's the most
> robust all-round meeting choice.

## 3. Verify

```
SwitchAudioSource -a    # lists every device; confirm the pairs you built appear
```

With both dropdowns on **Auto**, the recorder logs which device it chose. If you named
devices differently, set `MEETINGS_CAPTURE_DEVICE` / `MEETINGS_OUTPUT_DEVICE` (Alfred →
Configure Workflow) to force exact names, or adjust the detection names
`MEETINGS_DEV_JABRA` / `MEETINGS_DEV_BLUETOOTH` / `MEETINGS_DEV_BUILTIN_MIC` /
`MEETINGS_DEV_BUILTIN_OUT` (see `src/config.sh`).
