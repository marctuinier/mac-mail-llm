import Foundation

/// Shared constants for communication between the host app and the Mail extension
/// via the App Group container.
enum AppGroupConstants {
    /// The App Group identifier shared between the host app and extension.
    static let appGroupID = "UD763H597N.group.com.mailmate.ai"

    /// The URL scheme used by the extension to open the host app.
    static let urlScheme = "mailmate-ai"

    /// The URL used to open the compose assistant panel.
    static let composeURL = URL(string: "\(urlScheme)://compose")!

    /// UserDefaults suite backed by the shared App Group container.
    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID)!
    }

    /// The URL of the shared App Group container directory.
    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)!
    }

    // MARK: - File Paths

    /// Path to the email context JSON file written by the extension.
    static var emailContextFileURL: URL {
        containerURL.appendingPathComponent("email-context.json")
    }

    /// Path to the saved prompts JSON file.
    static var savedPromptsFileURL: URL {
        containerURL.appendingPathComponent("prompts.json")
    }

    /// Path to the tone samples JSON file.
    static var toneSamplesFileURL: URL {
        containerURL.appendingPathComponent("tone-samples.json")
    }

    // MARK: - UserDefaults Keys

    /// Key for the Gemini model preference.
    static let geminiModelKey = "gemini_model"

    /// Key for the default signature.
    static let defaultSignatureKey = "default_signature"

    /// Key for tracking whether onboarding has been completed.
    static let onboardingCompletedKey = "onboarding_completed"

    /// Key for the Keychain item storing the API key.
    static let apiKeyKeychainAccount = "com.mailmate.ai.gemini-api-key"

    // MARK: - Notification Names

    /// Posted by the host app when a generated reply is ready on the pasteboard.
    static let pasteReadyNotification = "com.mailmate.ai.pasteReady"

    /// Posted by the extension when new email context is available.
    static let emailContextUpdatedNotification = "com.mailmate.ai.emailContextUpdated"
}
