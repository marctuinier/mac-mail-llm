import Foundation

/// Service for reading and writing shared data in the App Group container.
/// Used by both the host app and the Mail extension.
final class SharedDataService {
    static let shared = SharedDataService()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let fileManager = FileManager.default

    private init() {
        ensureContainerExists()
    }

    // MARK: - Container Setup

    private func ensureContainerExists() {
        let url = AppGroupConstants.containerURL
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - Email Context

    /// Write email context from the Mail extension for the host app to read.
    func writeEmailContext(_ context: EmailContextModel) throws {
        let data = try encoder.encode(context)
        try data.write(to: AppGroupConstants.emailContextFileURL, options: .atomic)
    }

    /// Read the most recent email context written by the Mail extension.
    func readEmailContext() -> EmailContextModel? {
        guard let data = try? Data(contentsOf: AppGroupConstants.emailContextFileURL) else {
            return nil
        }
        return try? decoder.decode(EmailContextModel.self, from: data)
    }

    /// Clear the email context file.
    func clearEmailContext() {
        try? fileManager.removeItem(at: AppGroupConstants.emailContextFileURL)
    }

    // MARK: - Saved Prompts

    /// Load saved prompts from the shared container.
    func loadSavedPrompts() -> [SavedPrompt] {
        let fileURL = AppGroupConstants.savedPromptsFileURL

        // If no saved prompts file exists, load defaults from the app bundle
        if !fileManager.fileExists(atPath: fileURL.path) {
            return loadDefaultPrompts()
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return loadDefaultPrompts()
        }
        return (try? decoder.decode([SavedPrompt].self, from: data)) ?? loadDefaultPrompts()
    }

    /// Save prompts to the shared container.
    func saveSavedPrompts(_ prompts: [SavedPrompt]) throws {
        let data = try encoder.encode(prompts)
        try data.write(to: AppGroupConstants.savedPromptsFileURL, options: .atomic)
    }

    /// Load the default prompts from the app bundle.
    private func loadDefaultPrompts() -> [SavedPrompt] {
        guard let url = Bundle.main.url(forResource: "default-prompts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let prompts = try? decoder.decode([SavedPrompt].self, from: data)
        else {
            return []
        }

        // Also save them to the shared container for future use
        try? saveSavedPrompts(prompts)
        return prompts
    }

    // MARK: - Tone Samples

    /// Load tone samples from the shared container.
    func loadToneSamples() -> [ToneSample] {
        let fileURL = AppGroupConstants.toneSamplesFileURL
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        return (try? decoder.decode([ToneSample].self, from: data)) ?? []
    }

    /// Save tone samples to the shared container.
    func saveToneSamples(_ samples: [ToneSample]) throws {
        let data = try encoder.encode(samples)
        try data.write(to: AppGroupConstants.toneSamplesFileURL, options: .atomic)
    }

    // MARK: - Preferences

    /// The currently selected Gemini model.
    var geminiModel: String {
        get {
            AppGroupConstants.sharedDefaults.string(forKey: AppGroupConstants.geminiModelKey)
                ?? "gemini-2.5-pro"
        }
        set {
            AppGroupConstants.sharedDefaults.set(newValue, forKey: AppGroupConstants.geminiModelKey)
        }
    }

    /// The default email signature.
    var defaultSignature: String {
        get {
            AppGroupConstants.sharedDefaults.string(forKey: AppGroupConstants.defaultSignatureKey) ?? ""
        }
        set {
            AppGroupConstants.sharedDefaults.set(newValue, forKey: AppGroupConstants.defaultSignatureKey)
        }
    }

    /// Whether onboarding has been completed.
    var onboardingCompleted: Bool {
        get {
            AppGroupConstants.sharedDefaults.bool(forKey: AppGroupConstants.onboardingCompletedKey)
        }
        set {
            AppGroupConstants.sharedDefaults.set(newValue, forKey: AppGroupConstants.onboardingCompletedKey)
        }
    }
}
