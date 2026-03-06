import Foundation

/// Represents a single AI generation or refinement call, stored for audit/history.
struct CallRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let model: String
    let isRefine: Bool
    let status: Status
    let errorMessage: String?
    let promptTokens: Int?
    let candidateTokens: Int?
    let thoughtTokens: Int?
    let totalTokens: Int?
    let estimatedCostUSD: Double?
    let instruction: String
    let inputSummary: String
    let outputText: String?
    let thinkingText: String?
    let durationSeconds: Double?

    enum Status: String, Codable { case success, failure }
}

/// Token usage metadata returned by the Gemini API in the final streaming chunk.
struct UsageMetadata {
    let promptTokenCount: Int
    let candidatesTokenCount: Int
    let totalTokenCount: Int
    let thoughtsTokenCount: Int?
}

/// Persistent store for call history records in the App Group container.
enum CallHistoryStore {
    private static let maxEntries = 500

    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        return enc
    }()

    private static let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    static func loadAll() -> [CallRecord] {
        let url = AppGroupConstants.callHistoryFileURL
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder.decode([CallRecord].self, from: data)) ?? []
    }

    static func append(_ record: CallRecord) {
        var records = loadAll()
        records.append(record)

        if records.count > maxEntries {
            records = Array(records.suffix(maxEntries))
        }

        if let data = try? encoder.encode(records) {
            try? data.write(to: AppGroupConstants.callHistoryFileURL, options: .atomic)
        }

        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(AppGroupConstants.callHistoryUpdatedNotification),
            object: nil
        )
    }

    static func clear() {
        try? FileManager.default.removeItem(at: AppGroupConstants.callHistoryFileURL)
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(AppGroupConstants.callHistoryUpdatedNotification),
            object: nil
        )
    }

    // MARK: - Cost Estimation

    /// Per-million-token pricing (input, output) for supported models.
    /// Rates reflect published Gemini API pricing as of March 2026.
    private static let pricing: [String: (input: Double, output: Double)] = [
        "gemini-3.1-pro":        (2.00, 12.00),
        "gemini-3-flash":        (0.30,  2.50),
        "gemini-3.1-flash-lite": (0.10,  0.40),
        "gemini-2.5-pro":        (1.25, 10.00),
        "gemini-2.5-flash":      (0.30,  2.50),
        "gemini-2.5-flash-lite": (0.10,  0.40),
        "gemini-2.0-flash":      (0.10,  0.40),
        "gemini-2.0-flash-lite": (0.05,  0.20),
    ]

    static func estimateCost(model: String, promptTokens: Int, candidateTokens: Int) -> Double? {
        let key = pricing.keys.first(where: { model.hasPrefix($0) })
        guard let rates = key.flatMap({ pricing[$0] }) else { return nil }
        return (Double(promptTokens) * rates.input + Double(candidateTokens) * rates.output) / 1_000_000.0
    }
}
