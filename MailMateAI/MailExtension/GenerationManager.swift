import Foundation
import MailKit

/// Singleton that owns the Gemini generation lifecycle.
/// Survives toolbar popover dismissal so generation continues in the background
/// and results are available when the user reopens the panel.
final class GenerationManager {
    static let shared = GenerationManager()

    enum State: Equatable {
        case idle
        case generating
        case preview(html: String)
        case error(message: String)
    }

    // MARK: - Public State

    private(set) var state: State = .idle
    private(set) var streamingText: String = ""

    /// The Gemini client (maintains conversation history for refine)
    let geminiClient = ExtensionGeminiClient()

    /// Email context extracted from the compose session
    var emailContext: [String: Any] = [:]

    /// The compose session reference (weak to avoid retain cycles with Mail.app)
    weak var composeSession: MEComposeSession?

    // MARK: - Last Request (for retry)

    struct LastRequest {
        let apiKey: String
        let model: String
        let instruction: String
        let links: [(label: String, url: String)]
        let signature: String
        let toneSamples: [(label: String, text: String)]
        let isRefine: Bool
    }
    private(set) var lastRequest: LastRequest?

    // MARK: - Private

    private var generationTask: Task<Void, Never>?
    private let resultFileURL = AppGroupConstants.containerURL.appendingPathComponent("last-generation.json")

    private init() {
        // On init, check if there's a cached result from a previous run
        loadCachedResult()
    }

    // MARK: - Generate

    func generate(
        apiKey: String,
        model: String,
        instruction: String,
        links: [(label: String, url: String)],
        signature: String,
        toneSamples: [(label: String, text: String)],
        onThinkingUpdate: @escaping (String) -> Void,
        onStreamUpdate: @escaping (String) -> Void
    ) {
        generationTask?.cancel()
        state = .generating
        streamingText = ""
        clearCachedResult()

        lastRequest = LastRequest(
            apiKey: apiKey, model: model, instruction: instruction,
            links: links, signature: signature, toneSamples: toneSamples, isRefine: false
        )

        geminiClient.onThinking = { thinking in
            onThinkingUpdate(thinking)
        }
        geminiClient.onToken = { [weak self] partial in
            self?.streamingText = partial
            onStreamUpdate(partial)
        }

        let startTime = Date()
        let inputSummary = Self.buildInputSummary(from: emailContext)

        generationTask = Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let result = try await self.geminiClient.generateReply(
                    apiKey: apiKey, model: model,
                    emailContext: self.emailContext,
                    promptName: "", instruction: instruction,
                    links: links, signature: signature,
                    toneSamples: toneSamples
                )
                let duration = Date().timeIntervalSince(startTime)
                await MainActor.run {
                    self.state = .preview(html: result.text)
                    self.streamingText = ""
                    self.cacheResult(result.text)
                }
                Self.recordCall(
                    model: model, isRefine: false, status: .success,
                    instruction: instruction, inputSummary: inputSummary,
                    result: result, duration: duration
                )
            } catch {
                if Task.isCancelled { return }
                let duration = Date().timeIntervalSince(startTime)
                await MainActor.run {
                    self.state = .error(message: error.localizedDescription)
                }
                Self.recordCall(
                    model: model, isRefine: false, status: .failure,
                    instruction: instruction, inputSummary: inputSummary,
                    result: nil, duration: duration, errorMessage: error.localizedDescription
                )
            }
        }
    }

    // MARK: - Refine

    func refine(
        apiKey: String,
        model: String,
        instruction: String,
        onThinkingUpdate: @escaping (String) -> Void,
        onStreamUpdate: @escaping (String) -> Void
    ) {
        generationTask?.cancel()
        state = .generating
        streamingText = ""

        lastRequest = LastRequest(
            apiKey: apiKey, model: model, instruction: instruction,
            links: [], signature: "", toneSamples: [], isRefine: true
        )

        geminiClient.onThinking = { thinking in
            onThinkingUpdate(thinking)
        }
        geminiClient.onToken = { [weak self] partial in
            self?.streamingText = partial
            onStreamUpdate(partial)
        }

        let startTime = Date()
        let inputSummary = Self.buildInputSummary(from: emailContext)

        generationTask = Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let result = try await self.geminiClient.editReply(
                    apiKey: apiKey, model: model, instruction: instruction
                )
                let duration = Date().timeIntervalSince(startTime)
                await MainActor.run {
                    self.state = .preview(html: result.text)
                    self.streamingText = ""
                    self.cacheResult(result.text)
                }
                Self.recordCall(
                    model: model, isRefine: true, status: .success,
                    instruction: instruction, inputSummary: inputSummary,
                    result: result, duration: duration
                )
            } catch {
                if Task.isCancelled { return }
                let duration = Date().timeIntervalSince(startTime)
                await MainActor.run {
                    self.state = .error(message: error.localizedDescription)
                }
                Self.recordCall(
                    model: model, isRefine: true, status: .failure,
                    instruction: instruction, inputSummary: inputSummary,
                    result: nil, duration: duration, errorMessage: error.localizedDescription
                )
            }
        }
    }

    // MARK: - Call History

    private static func buildInputSummary(from context: [String: Any]) -> String {
        let subject = context["subject"] as? String ?? ""
        let from = context["fromAddress"] as? String ?? context["originalFrom"] as? String ?? ""
        if subject.isEmpty && from.isEmpty { return "New email" }
        var parts: [String] = []
        if !from.isEmpty { parts.append("From: \(from)") }
        if !subject.isEmpty { parts.append("Re: \(subject)") }
        return parts.joined(separator: " — ")
    }

    private static func recordCall(
        model: String,
        isRefine: Bool,
        status: CallRecord.Status,
        instruction: String,
        inputSummary: String,
        result: ExtensionGeminiClient.GenerationResult?,
        duration: TimeInterval,
        errorMessage: String? = nil
    ) {
        let usage = result?.usage
        let cost = usage.flatMap {
            CallHistoryStore.estimateCost(model: model, promptTokens: $0.promptTokenCount, candidateTokens: $0.candidatesTokenCount)
        }

        let record = CallRecord(
            id: UUID(),
            timestamp: Date(),
            model: model,
            isRefine: isRefine,
            status: status,
            errorMessage: errorMessage,
            promptTokens: usage?.promptTokenCount,
            candidateTokens: usage?.candidatesTokenCount,
            thoughtTokens: usage?.thoughtsTokenCount,
            totalTokens: usage?.totalTokenCount,
            estimatedCostUSD: cost,
            instruction: String(instruction.prefix(5000)),
            inputSummary: inputSummary,
            outputText: result?.text,
            thinkingText: result?.thinkingText,
            durationSeconds: duration
        )

        CallHistoryStore.append(record)
    }

    // MARK: - Reset

    func reset() {
        generationTask?.cancel()
        generationTask = nil
        state = .idle
        streamingText = ""
        geminiClient.reset()
        clearCachedResult()
    }

    // MARK: - Result Caching

    private func cacheResult(_ html: String) {
        let payload: [String: Any] = [
            "html": html,
            "timestamp": Date().timeIntervalSince1970
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? data.write(to: resultFileURL)
        }
    }

    private func clearCachedResult() {
        try? FileManager.default.removeItem(at: resultFileURL)
    }

    private func loadCachedResult() {
        guard let data = try? Data(contentsOf: resultFileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let html = json["html"] as? String,
              let ts = json["timestamp"] as? TimeInterval else { return }
        // Only restore if less than 10 minutes old
        let age = Date().timeIntervalSince1970 - ts
        if age < 600 && !html.isEmpty {
            state = .preview(html: html)
        } else {
            clearCachedResult()
        }
    }
}
