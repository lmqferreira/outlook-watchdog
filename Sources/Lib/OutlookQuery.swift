import AppKit
import Foundation

// MARK: - Outlook AppleScript Queries

public let outlookBundleID = "com.microsoft.Outlook"

public struct WindowInfo: Equatable, CustomStringConvertible {
    public let name: String
    public let id: Int
    public let visible: Bool

    public init(name: String, id: Int, visible: Bool) {
        self.name = name
        self.id = id
        self.visible = visible
    }

    public var description: String {
        "\(name.isEmpty ? "(unnamed)" : name) #\(id) \(visible ? "visible" : "hidden")"
    }
}

public func runAppleScript(_ source: String) -> String? {
    let script = NSAppleScript(source: source)
    var error: NSDictionary?
    let result = script?.executeAndReturnError(&error)
    if let error = error {
        let message = error[NSAppleScript.errorMessage] as? String ?? "unknown"
        log("AppleScript error: \(message)")
        return nil
    }
    return result?.stringValue
}

public func isOutlookRunning() -> Bool {
    NSRunningApplication.runningApplications(withBundleIdentifier: outlookBundleID).first != nil
}

public func getOutlookPID() -> pid_t? {
    NSRunningApplication.runningApplications(withBundleIdentifier: outlookBundleID).first?.processIdentifier
}

public func getOutlookWindows() -> [WindowInfo] {
    let script = """
    tell application "Microsoft Outlook"
        set output to ""
        repeat with w in windows
            set wName to name of w
            set wId to id of w
            set wVisible to visible of w
            set output to output & wName & "\\t" & wId & "\\t" & wVisible & "\\n"
        end repeat
        return output
    end tell
    """
    guard let result = runAppleScript(script) else { return [] }
    return parseWindowList(result)
}

/// Parse the tab-separated window list from AppleScript.
/// Exposed as a separate function for testability.
public func parseWindowList(_ raw: String) -> [WindowInfo] {
    raw.split(separator: "\n").compactMap { line in
        // Use components(separatedBy:) to preserve empty fields (e.g., unnamed windows)
        let parts = String(line).components(separatedBy: "\t")
        guard parts.count == 3,
              let id = Int(parts[1]) else { return nil }
        return WindowInfo(
            name: parts[0],
            id: id,
            visible: String(parts[2]) == "true"
        )
    }
}
