import Foundation
import MailKit

/// Per-session manager that owns the Gemini generation lifecycle for a single compose window.
/// Survives toolbar popover dismissal so generation continues in the background
/// and results are available when the user reopens the panel.
///
/// Each compose window gets its own instance, keyed by the session's context ID.
/// Instances are created when the session begins and removed when it ends.
final class GenerationManager {

    // MARK: - Session Registry

    private static var sessions: [UUID: GenerationManager] = [:]

    /// Retrieve or create a manager for the given compose session.
    static func manager(for session: MEComposeSession) -> GenerationManager {
        let id = session.composeContext.contextID
        if let existing = sessions[id] {
            return existing
        }
        let mgr = GenerationManager(sessionID: id)
        mgr.composeSession = session
        sessions[id] = mgr
        return mgr
    }

    /// Remove the manager when a compose session ends.
    static func removeManager(for session: MEComposeSession) {
        let id = session.composeContext.contextID
        sessions[id]?.generationTask?.cancel()
        sessions.removeValue(forKey: id)
    }

    /// Convenience for backward compatibility — returns the most recently active
    /// manager if there is exactly one, otherwise nil. Prefer `manager(for:)`.
    static var shared: GenerationManager? {
        sessions.values.first
    }

    // MARK: - State

    enum State: Equatable {
        case idle
        case generating
        case preview(html: String)
        case error(message: String)
    }

    let sessionID: UUID
    private(set) var state: State = .idle
    private(set) var streamingText: String = ""

    let geminiClient = ExtensionGeminiClient()
    var emailContext: [String: Any] = [:]
    weak var composeSession: MEComposeSession?
    var cachedOriginalRawData: Data?

    // MARK: - Last Request (for retry)

    struct LastRequest {
        let apiKey: String
        let model: String
        let instruction: String
        let links: [(label: String, url: String)]
        let signature: String
        let toneSamples: [(label: String, text: String)]
        let backgroundPrompts: [(name: String, instruction: String)]
        let isRefine: Bool
    }
    private(set) var lastRequest: LastRequest?

    // MARK: - Private

    fileprivate var generationTask: Task<Void, Never>?

    private init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    // MARK: - Generate

    func generate(
        apiKey: String,
        model: String,
        instruction: String,
        links: [(label: String, url: String)],
        signature: String,
        toneSamples: [(label: String, text: String)],
        backgroundPrompts: [(name: String, instruction: String)] = [],
        onThinkingUpdate: @escaping (String) -> Void,
        onStreamUpdate: @escaping (String) -> Void
    ) {
        generationTask?.cancel()
        state = .generating
        streamingText = ""

        lastRequest = LastRequest(
            apiKey: apiKey, model: model, instruction: instruction,
            links: links, signature: signature, toneSamples: toneSamples,
            backgroundPrompts: backgroundPrompts, isRefine: false
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
                    toneSamples: toneSamples,
                    backgroundPrompts: backgroundPrompts
                )
                let duration = Date().timeIntervalSince(startTime)
                await MainActor.run {
                    self.state = .preview(html: result.text)
                    self.streamingText = ""
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
            links: [], signature: "", toneSamples: [],
            backgroundPrompts: [], isRefine: true
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
    }
}
