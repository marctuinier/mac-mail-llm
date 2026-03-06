import Foundation

/// Append-only JSON-lines logger that captures each step of the MailMate pipeline
/// (extraction, generation, refinement) into a single file for debugging.
///
/// Each entry is a self-contained JSON object on its own line.
/// The log is capped at ~200KB; older entries are trimmed when the cap is exceeded.
enum FlowLogger {
    private static let maxBytes = 200_000

    static func log(step: String, data: [String: Any]) {
        var entry = data
        entry["_step"] = step
        entry["_timestamp"] = ISO8601DateFormatter().string(from: Date())

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
