// MeetingCapture — record a meeting as stereo (left = mic "Me", right = system/tap
// "Them") using a Core Audio process tap, with no BlackHole and no Audio MIDI Setup.
//
// One private aggregate device = the REAL microphone as clock master
// (kAudioAggregateDeviceMainSubDeviceKey) + a process tap of system (or per-app) audio.
// A single IOProc receives both, already sample-aligned, and writes mic -> left,
// tap mono-mix -> right into an AAC .m4a (matching record.sh's rec_*.m4a contract).
// The mic clocks the timeline continuously, so it never stalls when the far side is
// silent — the right channel is just zeros (and falls under transcribe.py's energy gate).
//
// TCC: the tap is gated by the MICROPHONE service, so this bundle carries
// NSMicrophoneUsageDescription and MUST be launched via `open` so it is its own
// responsible process (bare-binary launch makes the parent responsible -> silent zeros).
// See docs/adr/0001-*.md and the spike in src/spike/.
//
// Usage:  MeetingCapture --out <file.m4a> [--mic <UID|name>] [--pid PID]
//                        [--seconds N] [--list] [--log <path>]
//   --out      output .m4a (required for capture).
//   --mic      input device by CoreAudio UID or case-insensitive name substring
//              (e.g. "Jabra"); default = system default input.
//   --pid      scope the tap to one process (its system audio only); default = all audio.
//   --seconds  stop after N seconds; default 0 = run until SIGINT/SIGTERM (record.sh
//              stops it with `pkill -INT`).
//   --list     print input devices (name + UID + channels) and exit.
//   --log      mirror progress to this file (since `open` detaches stdout).

import AppKit
import AudioToolbox
import CoreAudio
import Foundation

// MARK: logging

var logPath = "/tmp/meetingcapture.log"
func log(_ s: String) {
    FileHandle.standardOutput.write((s + "\n").data(using: .utf8)!)
    let url = URL(fileURLWithPath: logPath)
    if !FileManager.default.fileExists(atPath: logPath) {
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile(); h.write((s + "\n").data(using: .utf8)!); try? h.close()
    }
}
func fail(_ s: String) -> Never { log("FATAL: \(s)"); exit(1) }

// MARK: system-audio-capture TCC authorization (macOS 14.4+; gates reading a process tap)
// On macOS 15+/26/27 reading a tap is gated by the private `kTCCServiceAudioCapture` TCC
// service, SEPARATE from Microphone. The Info.plist must carry `NSAudioCaptureUsageDescription`
// (note: the purpose string, NOT `NSSystemAudioCaptureUsageDescription`), but that key alone
// never auto-prompts for this service (unlike Microphone, which coreaudiod prompts for) — the
// app must explicitly request it via the private TCC framework (as insidegui/AudioCap does).
// An unauthorized tap delivers SILENCE (zeros), not an error, so without this the "Them"
// channel is just dead air. Graceful: any failure logs a warning and proceeds (Them stays
// silent, same as the existing far-side-silence fallback).
func ensureSystemAudioCaptureAuthorized() {
    typealias PreflightFn = @convention(c) (CFString, CFDictionary?) -> Int
    typealias RequestFn = @convention(c) (CFString, CFDictionary?, @convention(block) (Bool) -> Void) -> Void
    let service = "kTCCServiceAudioCapture" as CFString
    guard let h = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW) else {
        log("  WARN: couldn't load TCC framework — skipping system-audio auth (Them may be silent).")
        return
    }
    if let preSym = dlsym(h, "TCCAccessPreflight") {
        let preflight = unsafeBitCast(preSym, to: PreflightFn.self)
        let pf = preflight(service, nil)
        log("  system audio: preflight = \(pf)  (0=granted,1=denied,2=unknown)")
        if pf == 0 { log("  system audio: already authorized."); return }
    }
    guard let reqSym = dlsym(h, "TCCAccessRequest") else {
        log("  WARN: TCCAccessRequest unavailable — can't prompt for system audio (Them may be silent).")
        return
    }
    let request = unsafeBitCast(reqSym, to: RequestFn.self)
    // TCCAccessRequest presents its prompt from OUR process, so we need a live NSApplication
    // / WindowServer connection — a bare CoreAudio CLI silently hangs with no UI. Spin up an
    // accessory app (no Dock icon, like LSUIElement) and activate it so the prompt can show.
    let nsapp = NSApplication.shared
    nsapp.setActivationPolicy(.accessory)
    nsapp.activate(ignoringOtherApps: true)
    log("  requesting System Audio Recording permission — click Allow if macOS prompts…")
    var done = false, granted = false
    // Bind the completion to an explicit @convention(block) constant so it is a real
    // (heap) block that may escape — TCCAccessRequest holds it for its async reply, and an
    // inline trailing closure trips Swift's "@noescape closure has escaped" runtime trap.
    let completion: @convention(block) (Bool) -> Void = { g in granted = g; done = true }
    request(service, nil, completion)
    // The completion arrives via the app run loop; pump it (we're pre-CFRunLoopRun).
    let deadline = Date().addingTimeInterval(120)
    while !done, Date() < deadline { CFRunLoopRunInMode(.defaultMode, 0.1, true) }
    log(done ? "  system audio: \(granted ? "GRANTED" : "denied")."
             : "  system audio: request timed out (Them may be silent).")
}
func checkErr(_ status: OSStatus, _ what: String) {
    guard status != noErr else { return }
    var s = status.bigEndian
    let fourcc = withUnsafeBytes(of: &s) { raw -> String? in
        let b = raw.bindMemory(to: UInt8.self)
        return b.allSatisfy { $0 >= 32 && $0 < 127 } ? String(bytes: b, encoding: .ascii) : nil
    }
    fail("\(what) failed: \(status)\(fourcc.map { " '\($0)'" } ?? "")")
}

// MARK: Core Audio property helpers

func sysObjectID(_ selector: AudioObjectPropertySelector) -> AudioObjectID {
    var addr = AudioObjectPropertyAddress(mSelector: selector,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var dev = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    checkErr(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                        0, nil, &size, &dev), "get system object \(selector)")
    return dev
}
func cfStringProp(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
    var addr = AudioObjectPropertyAddress(mSelector: selector,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var str: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    _ = withUnsafeMutablePointer(to: &str) {
        AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, $0)
    }
    return str as String
}
func audioObject(forPID pid: pid_t) -> AudioObjectID {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var inPID = pid
    var obj = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    checkErr(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                        UInt32(MemoryLayout<pid_t>.size), &inPID, &size, &obj),
             "TranslatePIDToProcessObject(\(pid))")
    return obj
}

// MARK: input-device enumeration / selection

func allAudioDevices() -> [AudioObjectID] {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr
    else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
    else { return [] }
    return ids
}
func inputChannelCount(_ dev: AudioObjectID) -> Int {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                          mScope: kAudioObjectPropertyScopeInput,
                                          mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(dev, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, raw) == noErr else { return 0 }
    let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
    return list.reduce(0) { $0 + Int($1.mNumberChannels) }
}
func inputDevices() -> [AudioObjectID] { allAudioDevices().filter { inputChannelCount($0) > 0 } }

/// Resolve the mic: exact UID, then case-insensitive name/UID substring, else default input.
func resolveMic(_ arg: String?) -> AudioObjectID {
    let def = sysObjectID(kAudioHardwarePropertyDefaultInputDevice)
    guard let arg, !arg.isEmpty else { return def }
    let inputs = inputDevices()
    if let m = inputs.first(where: { cfStringProp($0, kAudioDevicePropertyDeviceUID) == arg }) { return m }
    let lc = arg.lowercased()
    if let m = inputs.first(where: {
        cfStringProp($0, kAudioObjectPropertyName).lowercased().contains(lc)
            || cfStringProp($0, kAudioDevicePropertyDeviceUID).lowercased().contains(lc)
    }) { return m }
    log("  WARN: no input device matched \"\(arg)\" — falling back to default input.")
    return def
}

// MARK: args

var outPath: String?
var micArg: String?
var scopePID: pid_t?
var seconds = 0.0
do {
    let a = CommandLine.arguments
    var i = 1
    while i < a.count {
        switch a[i] {
        case "--out": i += 1; outPath = a[i]
        case "--mic": i += 1; micArg = a[i]
        case "--pid": i += 1; scopePID = pid_t(a[i]) ?? nil
        case "--seconds": i += 1; seconds = Double(a[i]) ?? 0
        case "--log": i += 1; logPath = a[i]
        case "--list":
            for d in inputDevices() {
                print("\(cfStringProp(d, kAudioObjectPropertyName))  "
                    + "[\(cfStringProp(d, kAudioDevicePropertyDeviceUID))]  \(inputChannelCount(d))ch")
            }
            exit(0)
        default: log("ignoring arg: \(a[i])")
        }
        i += 1
    }
}
try? "".write(to: URL(fileURLWithPath: logPath), atomically: true, encoding: .utf8)
guard let outPath, !outPath.isEmpty else { fail("--out <file.m4a> is required") }
log("MeetingCapture")
log("  out:     \(outPath)")

// MARK: resolve mic (clock master)

let micDev = resolveMic(micArg)
let micUID = cfStringProp(micDev, kAudioDevicePropertyDeviceUID)
log("  mic:     \(cfStringProp(micDev, kAudioObjectPropertyName))  [\(micUID)]"
    + (micArg.map { "  (requested \"\($0)\")" } ?? ""))

// MARK: process tap (Them)

// Authorize system-audio capture BEFORE creating/reading the tap, or it yields silence.
ensureSystemAudioCaptureAuthorized()

let tapDesc: CATapDescription
if let pid = scopePID {
    log("  tap:     ONLY pid \(pid)")
    tapDesc = CATapDescription(stereoMixdownOfProcesses: [audioObject(forPID: pid)])
} else {
    log("  tap:     GLOBAL (all system audio)")
    tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
}
tapDesc.name = "AlfredMeetings Capture"
tapDesc.isPrivate = true
tapDesc.muteBehavior = .unmuted  // keep hearing the call while we tap it
var tapID = AudioObjectID(kAudioObjectUnknown)
checkErr(AudioHardwareCreateProcessTap(tapDesc, &tapID), "AudioHardwareCreateProcessTap")
// NB: Swift `defer` does NOT run on exit()/exit(3), and this program only ever leaves via
// exit(); so every teardown is explicit (finishAndExit / the start-failure path) rather
// than deferred — otherwise a failed start would leak the aggregate + tap.

// MARK: aggregate = mic (clock master) + tap

let aggUID = "com.maybeitssquid.alfredmeetings.capture.\(UUID().uuidString)"
let aggDesc: [String: Any] = [
    kAudioAggregateDeviceNameKey: "AlfredMeetings Capture",
    kAudioAggregateDeviceUIDKey: aggUID,
    kAudioAggregateDeviceIsPrivateKey: true,
    kAudioAggregateDeviceIsStackedKey: false,
    kAudioAggregateDeviceMainSubDeviceKey: micUID,
    kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: micUID]],
    // MUST be false: with tap auto-start on, the aggregate waits for the tap to deliver
    // its first buffer before it begins clocking, so starting `rec` in SILENCE (before the
    // far side talks) never gets an IOProc callback and startConfirmed() fails. With it
    // off, the mic (clock master) drives the IOProc immediately and the tap fills the right
    // channel as soon as system audio appears. (Verified: true => FAIL in silence, false => OK.)
    kAudioAggregateDeviceTapAutoStartKey: false,
    kAudioAggregateDeviceTapListKey: [
        [kAudioSubTapUIDKey: tapDesc.uuid.uuidString,
         kAudioSubTapDriftCompensationKey: true],
    ],
]
var aggID = AudioObjectID(kAudioObjectUnknown)
checkErr(AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggID),
         "AudioHardwareCreateAggregateDevice")

var sampleRate: Float64 = 48000
do {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<Float64>.size)
    _ = AudioObjectGetPropertyData(aggID, &addr, 0, nil, &size, &sampleRate)
}
log(String(format: "  agg:     id %u @ %.0f Hz (mic = clock master)", aggID, sampleRate))

// MARK: output .m4a (AAC). Client = interleaved stereo float; ExtAudioFile encodes to AAC.

var fileRef: ExtAudioFileRef?
do {
    var dst = AudioStreamBasicDescription()
    dst.mFormatID = kAudioFormatMPEG4AAC
    dst.mSampleRate = sampleRate
    dst.mChannelsPerFrame = 2
    var dstSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    checkErr(AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, nil, &dstSize, &dst),
             "fill out AAC ASBD")
    let url = URL(fileURLWithPath: outPath)
    try? FileManager.default.removeItem(at: url)
    checkErr(ExtAudioFileCreateWithURL(url as CFURL, kAudioFileM4AType, &dst, nil,
                                       AudioFileFlags.eraseFile.rawValue, &fileRef),
             "ExtAudioFileCreateWithURL(.m4a)")
    var client = AudioStreamBasicDescription(
        mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
        mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
    checkErr(ExtAudioFileSetProperty(fileRef!, kExtAudioFileProperty_ClientDataFormat,
                                     UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &client),
             "set client format")
    checkErr(ExtAudioFileWriteAsync(fileRef!, 0, nil), "prime async write")
}

// MARK: IOProc — mic(L) + tap mono(R) -> file

final class Ctx {
    let file: ExtAudioFileRef
    let cap = 16384
    let out: UnsafeMutablePointer<Float>
    var abl: AudioBufferList
    var calls: UInt64 = 0, frames: UInt64 = 0
    var micPeak: Float = 0, tapPeak: Float = 0
    init(_ f: ExtAudioFileRef) {
        file = f
        out = .allocate(capacity: cap * 2)
        abl = AudioBufferList(mNumberBuffers: 1,
                              mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: 0, mData: out))
    }
}
let ctx = Ctx(fileRef!)
let ctxPtr = Unmanaged.passUnretained(ctx).toOpaque()

let ioProc: AudioDeviceIOProc = { _, _, inData, _, _, _, clientData in
    guard let clientData else { return noErr }
    let ctx = Unmanaged<Ctx>.fromOpaque(clientData).takeUnretainedValue()
    ctx.calls += 1
    let bufs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
    guard bufs.count >= 1 else { return noErr }
    let micBuf = bufs[0]                     // sub-device (mic) first
    let tapBuf = bufs[bufs.count - 1]        // tap appended last
    let micCh = max(Int(micBuf.mNumberChannels), 1)
    let tapCh = max(Int(tapBuf.mNumberChannels), 1)
    guard let micData = micBuf.mData, let tapData = tapBuf.mData else { return noErr }
    let micN = Int(micBuf.mDataByteSize) / (4 * micCh)
    let tapN = Int(tapBuf.mDataByteSize) / (4 * tapCh)
    let sameBuf = bufs.count < 2
    let n = min(micN, sameBuf ? micN : tapN, ctx.cap)
    let mic = micData.bindMemory(to: Float.self, capacity: micN * micCh)
    let tap = tapData.bindMemory(to: Float.self, capacity: tapN * tapCh)
    for i in 0..<n {
        let l = mic[i * micCh]               // Me = mic channel 0
        var r: Float = 0                     // Them = tap mono mix
        if sameBuf {
            if micCh > 1 { for c in 1..<micCh { r += mic[i * micCh + c] }; r /= Float(micCh - 1) }
        } else {
            for c in 0..<tapCh { r += tap[i * tapCh + c] }
            r /= Float(tapCh)
        }
        ctx.out[2 * i] = l
        ctx.out[2 * i + 1] = r
        if abs(l) > ctx.micPeak { ctx.micPeak = abs(l) }
        if abs(r) > ctx.tapPeak { ctx.tapPeak = abs(r) }
    }
    ctx.abl.mBuffers.mDataByteSize = UInt32(n * 2 * 4)
    let st = withUnsafePointer(to: &ctx.abl) { ExtAudioFileWriteAsync(ctx.file, UInt32(n), $0) }
    if st == noErr { ctx.frames += UInt64(n) }
    return st
}

var procID: AudioDeviceIOProcID?
checkErr(AudioDeviceCreateIOProcID(aggID, ioProc, ctxPtr, &procID), "AudioDeviceCreateIOProcID")

// MARK: start with confirmation (a tap-only aggregate won't clock; churn can race the start)

func startConfirmed(maxAttempts: Int = 3, perAttempt: TimeInterval = 1.5) -> Bool {
    for attempt in 1...maxAttempts {
        let before = ctx.calls
        checkErr(AudioDeviceStart(aggID, procID), "AudioDeviceStart")
        let deadline = Date().addingTimeInterval(perAttempt)
        while Date() < deadline {
            if ctx.calls > before { return true }
            usleep(50_000)
        }
        log("  start attempt \(attempt)/\(maxAttempts): no IOProc callback in \(perAttempt)s — retrying…")
        AudioDeviceStop(aggID, procID)
        usleep(300_000)
    }
    return false
}

log("  If macOS shows a Microphone prompt, click Allow.")
guard startConfirmed() else {
    log("FAIL: capture never started — mic unavailable, permission denied, or a startup race.")
    AudioDeviceDestroyIOProcID(aggID, procID!)
    ExtAudioFileDispose(fileRef!)
    try? FileManager.default.removeItem(at: URL(fileURLWithPath: outPath))  // no 0-frame file
    AudioHardwareDestroyAggregateDevice(aggID)
    AudioHardwareDestroyProcessTap(tapID)
    exit(3)
}
log("🔴 recording (start confirmed)\(seconds > 0 ? " for \(Int(seconds))s" : " — stop with SIGINT")")

// MARK: run until SIGINT/SIGTERM (record.sh uses `pkill -INT`), or --seconds elapses

func finishAndExit() -> Never {
    AudioDeviceStop(aggID, procID)
    AudioDeviceDestroyIOProcID(aggID, procID!)
    ExtAudioFileDispose(fileRef!)          // finalizes the .m4a (writes magic cookie)
    AudioHardwareDestroyAggregateDevice(aggID)
    AudioHardwareDestroyProcessTap(tapID)
    func dB(_ x: Float) -> String { x > 0 ? String(format: "%.1f dBFS", 20 * log10(x)) : "-inf" }
    log(String(format: "⏹ stopped: %llu frames (%.1fs), Me %@, Them %@ -> %@",
               ctx.frames, Double(ctx.frames) / sampleRate, dB(ctx.micPeak), dB(ctx.tapPeak), outPath))
    exit(0)
}

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
for src in [sigint, sigterm] { src.setEventHandler { finishAndExit() }; src.resume() }
if seconds > 0 {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { finishAndExit() }
}
CFRunLoopRun()
