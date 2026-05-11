import Foundation

// MARK: - Logger

private let logDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
}()

private let pid = ProcessInfo.processInfo.processIdentifier

private let logFileHandle: FileHandle? = {
    let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs")
    let path = dir.appendingPathComponent("outlook-watchdog.log")

    // Create file if it doesn't exist (append mode — never overwrite)
    if !FileManager.default.fileExists(atPath: path.path) {
        FileManager.default.createFile(atPath: path.path, contents: nil)
    }

    guard let handle = try? FileHandle(forWritingTo: path) else { return nil }
    handle.seekToEndOfFile()
    return handle
}()

public func log(_ message: String) {
    let ts = logDateFormatter.string(from: Date())
    let line = "[\(ts)] [\(pid)] \(message)\n"

    // stdout
    print(line, terminator: "")
    fflush(stdout)

    // log file (append)
    if let data = line.data(using: .utf8) {
        logFileHandle?.write(data)
    }
}
