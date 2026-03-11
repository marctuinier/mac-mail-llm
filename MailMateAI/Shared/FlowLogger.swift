import Foundation

/// Append-only JSON-lines logger that captures each step of the MailMate pipeline
/// (extraction, generation, refinement) into a single file for debugging.
///
/// Each entry is a self-contained JSON object on its own line.
/// The log is capped at ~200KB; older entries are trimmed when the cap is exceeded.
///
/// Additionally, each "generate" step starts a new per-session log file that
/// captures all steps for that single request, written to the App Group container
/// as `session-log-<timestamp>.json`.
enum FlowLogger {
    private static let maxBytes = 200_000
    private static var sessionEntries: [[String: Any]] = []
    private static var sessionActive = false

    static func log(step: String, data: [String: Any]) {
        var entry = data
        entry["_step"] = step
        entry["_timestamp"] = ISO8601DateFormatter().string(from: Date())

        // Per-session log: start fresh on "generate", collect until "generate_result"
        if step == "generate" || step == "extraction" && !sessionActive {
            sessionEntries = []
            sessionActive = true
        }
        if sessionActive {
            sessionEntries.append(entry)
        }
        if step == "generate_result" || step == "stream_complete" {
            writeSessionLog()
        }

        guard let json = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              let line = String(data: json, encoding: .utf8) else { return }

        let url = AppGroupConstants.flowLogFileURL
        let newLine = line + "\n"

        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(newLine.utf8))
                handle.closeFile()
            }
        } else {
            try? Data(newLine.utf8).write(to: url)
        }

        trimIfNeeded(url: url)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: AppGroupConstants.flowLogFileURL)
    }

    /// Write the collected session entries as a pretty-printed JSON array.
    private static func writeSessionLog() {
        guard !sessionEntries.isEmpty else { return }
        sessionActive = false

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "session-log-\(formatter.string(from: Date())).json"
        let url = AppGroupConstants.containerURL.appendingPathComponent(filename)

        if let data = try? JSONSerialization.data(withJSONObject: sessionEntries, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }

        // Also write the latest session log to a stable filename for easy access
        let latestURL = AppGroupConstants.containerURL.appendingPathComponent("latest-session-log.json")
        if let data = try? JSONSerialization.data(withJSONObject: sessionEntries, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: latestURL, options: .atomic)
        }

        sessionEntries = []
    }

    private static func trimIfNeeded(url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size > maxBytes else { return }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: "\n")
        let half = lines.count / 2
        let trimmed = lines.suffix(from: half).joined(separator: "\n")
        try? trimmed.write(to: url, atomically: true, encoding: .utf8)
    }
}
