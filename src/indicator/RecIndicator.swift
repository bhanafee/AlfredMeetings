// RecIndicator — a tiny menu-bar status item shown while AlfredMeetings is recording.
//
// record.sh launches this app (via `open -n -a … --args --stamp <stamp> --stop <path>`)
// right after a recording starts, and kills it by argv match (`pkill -f
// RecIndicator.app.*<stamp>`) when the recording stops. It is an accessory app
// (LSUIElement) so it has no Dock icon. Clicking it offers "Stop recording", which runs
// the toggle script passed on argv — the same stop path used everywhere else.
//
// Built and ad-hoc-signed at install time by setup/install.sh (no external deps).

import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var blinkTimer: Timer?
    private var elapsedTimer: Timer?
    private var bright = true
    private let started = Date()
    private var stopPath: String?

    func applicationDidFinishLaunching(_ note: Notification) {
        // Parse argv: --stop <path-to-record.sh>  (--stamp is only for pkill matching).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--stop"), i + 1 < args.count {
            stopPath = args[i + 1]
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.toolTip = "AlfredMeetings — recording"
        }
        render()

        let menu = NSMenu()
        let header = NSMenuItem(title: "Recording…", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Stop recording",
                                action: #selector(stop), keyEquivalent: ""))
        statusItem.menu = menu

        // Blink the dot so it reads as "live", and update the elapsed time in the menu.
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.bright.toggle()
            self?.render()
        }
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let secs = Int(Date().timeIntervalSince(self.started))
            header.title = String(format: "Recording — %02d:%02d", secs / 60, secs % 60)
        }

        // If record.sh kills us via pkill it sends SIGTERM; exit cleanly either way.
        signal(SIGTERM, SIG_DFL)
        signal(SIGINT, SIG_DFL)
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let color = bright ? NSColor.systemRed : NSColor.systemRed.withAlphaComponent(0.35)
        button.attributedTitle = NSAttributedString(
            string: "●",
            attributes: [.foregroundColor: color,
                         .font: NSFont.systemFont(ofSize: 14)])
    }

    @objc private func stop() {
        if let path = stopPath {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [path]
            try? p.run()   // independent process; survives our termination
        }
        // record.sh's stop path will pkill us; terminate anyway as a fallback.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
