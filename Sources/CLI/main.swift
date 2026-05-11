import AppKit
import Foundation
import OutlookWatchdogLib

// MARK: - Main Entry Point

class AppDelegate: NSObject, NSApplicationDelegate {
    let pollInterval: TimeInterval
    let detector = ZombieDetector()
    var pollTimer: Timer?
    var lastOutlookPID: pid_t?

    init(pollInterval: TimeInterval) {
        self.pollInterval = pollInterval
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("outlook-watchdog started (poll every \(Int(pollInterval))s)")

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }

        // Run an initial poll immediately
        poll()
    }

    private func poll() {
        guard let pid = getOutlookPID() else {
            if lastOutlookPID != nil {
                log("Outlook quit (was PID \(lastOutlookPID!))")
                lastOutlookPID = nil
                detector.reset()
            }
            return
        }

        if lastOutlookPID != nil && lastOutlookPID != pid {
            log("Outlook restarted (PID \(lastOutlookPID!) → \(pid))")
            detector.reset()
        }
        lastOutlookPID = pid

        let windows = getOutlookWindows()
        if windows.isEmpty { return }
        let processInfo = getOutlookProcessInfo()

        if let report = detector.analyze(windows: windows, processInfo: processInfo) {
            log(report.description)
        }
    }
}

// MARK: - CLI

let args = CommandLine.arguments
var pollInterval: TimeInterval = 5

if let idx = args.firstIndex(of: "--interval"), idx + 1 < args.count,
   let val = TimeInterval(args[idx + 1]) {
    pollInterval = val
}

if args.contains("--help") || args.contains("-h") {
    print("""
    outlook-watchdog — Monitors New Outlook for Mac for zombie window leaks

    Detects and logs zombie (hidden, leaked) windows that accumulate when
    closing and reopening the Outlook main window. Each zombie leaks a
    WebKit WebContent process and ~120 MB of RAM.

    Usage:
      outlook-watchdog [--interval <seconds>]

    Options:
      --interval <seconds>  Polling interval (default: 5)
      --help, -h            Show this help
    """)
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate(pollInterval: pollInterval)
app.delegate = delegate
app.run()
