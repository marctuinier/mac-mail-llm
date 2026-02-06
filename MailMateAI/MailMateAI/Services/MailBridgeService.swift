import AppKit
import Foundation

/// Service that bridges between the host app and Mail.app by using AppleScript
/// to activate Mail and paste content from the system clipboard into the compose window.
final class MailBridgeService {
    static let shared = MailBridgeService()

    private init() {}

    /// Place HTML on the pasteboard and paste it into the frontmost Mail compose window.
    /// This activates Mail.app, selects all text in the compose body, and pastes the
    /// rich-text content from the clipboard.
    ///
    /// - Parameter html: The HTML content to insert into the compose window.
    func insertIntoMail(html: String) async throws {
        // Step 1: Place HTML on the pasteboard
        try PasteboardService.shared.placeOnPasteboard(html: html)

        // Step 2: Small delay to ensure pasteboard is ready
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // Step 3: Execute AppleScript to paste into Mail
        try await executePasteScript()
    }

    /// Activates Mail.app and pastes clipboard content into the compose window.
    /// Uses GUI scripting via System Events to simulate keyboard shortcuts.
    @MainActor
    private func executePasteScript() async throws {
        let script = """
        tell application "Mail" to activate
        delay 0.3
        tell application "System Events"
            tell process "Mail"
                -- Select all text in the compose body
                keystroke "a" using command down
                delay 0.15
                -- Paste the rich text from clipboard
                keystroke "v" using command down
            end tell
        end tell
        """

        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw MailBridgeError.scriptCreationFailed
        }

        appleScript.executeAndReturnError(&errorInfo)

        if let errorInfo = errorInfo {
            let errorMessage = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            throw MailBridgeError.scriptExecutionFailed(message: errorMessage)
        }
    }

    /// Check if the app has accessibility permissions (needed for GUI scripting).
    /// Does NOT prompt the user -- use `requestAccessibilityPermission()` for that.
    func checkAccessibilityPermission() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Prompt the user to grant accessibility permissions if not already granted.
    @MainActor
    func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

// MARK: - Errors

enum MailBridgeError: LocalizedError {
    case scriptCreationFailed
    case scriptExecutionFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .scriptCreationFailed:
            return "Failed to create the AppleScript for Mail integration."
        case .scriptExecutionFailed(let message):
            return "AppleScript execution failed: \(message)"
        }
    }
}
