import Foundation

// MARK: - Window Classification

public enum WindowCategory: String, CustomStringConvertible {
    case main       // Inbox, Calendar, Mail — the primary windows
    case companion  // Unnamed windows paired with main windows
    case reminder   // Reminder popup windows
    case unknown    // Anything else

    public var description: String { rawValue }
}

public func classifyWindow(_ window: WindowInfo) -> WindowCategory {
    let name = window.name
    if name.isEmpty {
        return .companion
    }
    if name.starts(with: "Inbox") || name.starts(with: "Calendar") || name.starts(with: "Mail") {
        return .main
    }
    if name.contains("Reminder") {
        return .reminder
    }
    return .unknown
}

// MARK: - Snapshot

public struct WindowSnapshot: Equatable {
    public let timestamp: Date
    public let windows: [WindowInfo]

    public init(timestamp: Date = Date(), windows: [WindowInfo]) {
        self.timestamp = timestamp
        self.windows = windows
    }

    public var visibleWindows: [WindowInfo] { windows.filter { $0.visible } }
    public var hiddenWindows: [WindowInfo] { windows.filter { !$0.visible } }

    public var visibleMainCount: Int {
        visibleWindows.filter { classifyWindow($0) == .main }.count
    }

    public var hiddenMainCount: Int {
        hiddenWindows.filter { classifyWindow($0) == .main }.count
    }

    public var hiddenCompanionCount: Int {
        hiddenWindows.filter { classifyWindow($0) == .companion }.count
    }

    /// Zombie main windows: hidden main windows beyond the 1 that Outlook normally keeps.
    /// After a fresh launch, Outlook may have 0-1 hidden main windows. Anything beyond that is a zombie.
    public var zombieMainCount: Int {
        max(0, hiddenMainCount - 1)
    }

    /// Zombie companion windows: hidden companions beyond the expected count.
    /// Each main window (visible or first hidden) normally has 1 companion.
    /// Extra companions are from zombie main windows.
    public var zombieCompanionCount: Int {
        let expectedCompanions = visibleMainCount + min(1, hiddenMainCount)
        return max(0, hiddenCompanionCount - expectedCompanions)
    }

    public var totalZombieCount: Int {
        zombieMainCount + zombieCompanionCount
    }

    public var hasZombies: Bool {
        totalZombieCount > 0
    }
}

// MARK: - Zombie Detector

public class ZombieDetector {
    private var previousSnapshot: WindowSnapshot?
    private var previousProcessInfo: OutlookProcessInfo?

    public init() {}

    /// Reset state — call when Outlook restarts (new PID) so deltas don't span sessions.
    public func reset() {
        previousSnapshot = nil
        previousProcessInfo = nil
    }

    /// Analyze a new set of windows. Returns a report if state changed, nil if unchanged.
    public func analyze(windows: [WindowInfo], processInfo: OutlookProcessInfo?) -> ZombieReport? {
        let snapshot = WindowSnapshot(windows: windows)
        defer {
            previousSnapshot = snapshot
            previousProcessInfo = processInfo
        }

        // Always report on first run
        guard let prev = previousSnapshot else {
            return makeReport(snapshot: snapshot, processInfo: processInfo, delta: nil)
        }

        // Only report when something meaningful changed
        let delta = computeDelta(from: prev, to: snapshot, prevProcess: previousProcessInfo, newProcess: processInfo)
        if delta.isSignificant {
            return makeReport(snapshot: snapshot, processInfo: processInfo, delta: delta)
        }

        return nil
    }

    private func makeReport(snapshot: WindowSnapshot, processInfo: OutlookProcessInfo?, delta: ZombieDelta?) -> ZombieReport {
        ZombieReport(
            totalWindows: snapshot.windows.count,
            visibleCount: snapshot.visibleWindows.count,
            hiddenCount: snapshot.hiddenWindows.count,
            zombieMainCount: snapshot.zombieMainCount,
            zombieCompanionCount: snapshot.zombieCompanionCount,
            totalZombieCount: snapshot.totalZombieCount,
            processInfo: processInfo,
            delta: delta
        )
    }

    private func computeDelta(from prev: WindowSnapshot, to curr: WindowSnapshot,
                               prevProcess: OutlookProcessInfo?, newProcess: OutlookProcessInfo?) -> ZombieDelta {
        ZombieDelta(
            windowCountChange: curr.windows.count - prev.windows.count,
            zombieCountChange: curr.totalZombieCount - prev.totalZombieCount,
            visibleCountChange: curr.visibleWindows.count - prev.visibleWindows.count,
            memoryChangeMB: (newProcess?.totalMB ?? 0) - (prevProcess?.totalMB ?? 0),
            webContentChange: (newProcess?.webContentCount ?? 0) - (prevProcess?.webContentCount ?? 0)
        )
    }
}

// MARK: - Reports

public struct ZombieDelta: Equatable {
    public let windowCountChange: Int
    public let zombieCountChange: Int
    public let visibleCountChange: Int
    public let memoryChangeMB: Int
    public let webContentChange: Int

    public var isSignificant: Bool {
        windowCountChange != 0 || zombieCountChange != 0 || visibleCountChange != 0
    }

    var description: String {
        var parts: [String] = []
        if windowCountChange != 0 { parts.append("windows \(signed(windowCountChange))") }
        if zombieCountChange != 0 { parts.append("zombies \(signed(zombieCountChange))") }
        if visibleCountChange != 0 { parts.append("visible \(signed(visibleCountChange))") }
        if memoryChangeMB != 0 { parts.append("memory \(signed(memoryChangeMB)) MB") }
        if webContentChange != 0 { parts.append("WebContent \(signed(webContentChange))") }
        return parts.isEmpty ? "no change" : parts.joined(separator: ", ")
    }

    private func signed(_ n: Int) -> String {
        n > 0 ? "+\(n)" : "\(n)"
    }
}

public struct ZombieReport: CustomStringConvertible {
    public let totalWindows: Int
    public let visibleCount: Int
    public let hiddenCount: Int
    public let zombieMainCount: Int
    public let zombieCompanionCount: Int
    public let totalZombieCount: Int
    public let processInfo: OutlookProcessInfo?
    public let delta: ZombieDelta?

    public var description: String {
        var line = "windows: \(totalWindows) (visible: \(visibleCount), hidden: \(hiddenCount))"
        if totalZombieCount > 0 {
            line += " | ZOMBIES: \(totalZombieCount) (main: \(zombieMainCount), companion: \(zombieCompanionCount))"
        }
        if let pi = processInfo {
            line += " | \(pi)"
        }
        if let d = delta {
            line += " | Δ \(d.description)"
        }
        return line
    }
}
