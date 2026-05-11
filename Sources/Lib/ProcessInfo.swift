import Foundation

// MARK: - Process Memory Info

public struct OutlookProcessInfo: Equatable, CustomStringConvertible {
    public let outlookRSSMB: Int
    public let webContentCount: Int
    public let webContentRSSMB: Int

    public var totalMB: Int { outlookRSSMB + webContentRSSMB }

    public var description: String {
        "Outlook: \(outlookRSSMB) MB, WebContent: \(webContentCount) procs / \(webContentRSSMB) MB, total: \(totalMB) MB"
    }
}

public func getOutlookProcessInfo() -> OutlookProcessInfo? {
    guard isOutlookRunning() else { return nil }

    guard let output = runShell("/bin/ps", arguments: ["aux"]) else { return nil }

    var outlookKB = 0
    var wcCount = 0
    var wcKB = 0

    for line in output.split(separator: "\n") {
        let cols = line.split(separator: " ", omittingEmptySubsequences: true)
        guard cols.count >= 6, let rss = Int(cols[5]) else { continue }

        if line.contains("Microsoft Outlook") {
            outlookKB += rss
        }
        if line.contains("WebContent") && line.contains("WebKit") {
            wcCount += 1
            wcKB += rss
        }
    }

    return OutlookProcessInfo(
        outlookRSSMB: outlookKB / 1024,
        webContentCount: wcCount,
        webContentRSSMB: wcKB / 1024
    )
}

/// Run a shell command and return stdout. Avoids pipe deadlock by reading before waiting.
private func runShell(_ path: String, arguments: [String]) -> String? {
    let pipe = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
    } catch {
        return nil
    }

    // Read data BEFORE waitUntilExit to avoid pipe buffer deadlock
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    return String(data: data, encoding: .utf8)
}
