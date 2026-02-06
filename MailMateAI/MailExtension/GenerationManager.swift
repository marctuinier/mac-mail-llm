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
        onStreamUpdate: @escaping (String) -> Void
    ) {
        // Cancel any in-flight generation
        generationTask?.cancel()
        state = .generating
        streamingText = ""
        clearCachedResult()

        geminiClient.onToken = { [weak self] partial in
            self?.streamingText = partial
            onStreamUpdate(partial)
        }

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
                await MainActor.run {
                    self.state = .preview(html: result)
                    self.streamingText = ""
                    self.cacheResult(result)
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.state = .error(message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Refine

    func refine(
        apiKey: String,
        model: String,
        instruction: String,
        onStreamUpdate: @escaping (String) -> Void
    ) {
        generationTask?.cancel()
        state = .generating
        streamingText = ""

        geminiClient.onToken = { [weak self] partial in
            self?.streamingText = partial
            onStreamUpdate(partial)
        }

        generationTask = Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let result = try await self.geminiClient.editReply(
                    apiKey: apiKey, model: model, instruction: instruction
                )
                await MainActor.run {
                    self.state = .preview(html: result)
                    self.streamingText = ""
                    self.cacheResult(result)
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.state = .error(message: error.localizedDescription)
                }
            }
        }
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
