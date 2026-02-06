import MailKit
import Foundation

/// The principal class for the Mail compose extension.
/// Mail.app instantiates this handler whenever a compose window is opened.
class ComposeSessionHandler: NSObject, MEComposeSessionHandler {

    // MARK: - Session Lifecycle

    /// Called when a new compose session begins (user opens a compose window).
    func mailComposeSessionDidBegin(_ session: MEComposeSession) {
        // Email context is now extracted later by ToolbarViewController using
        // session.composeContext.originalMessage, which has the actual email body.
    }

    /// Called when the compose session ends (window is closed or email is sent).
    func mailComposeSessionDidEnd(_ session: MEComposeSession) {
        // Clean up is optional; context will be overwritten by the next session.
    }

    // MARK: - Toolbar View Controller

    /// Returns a view controller that Mail.app embeds in the compose toolbar.
    func viewController(for session: MEComposeSession) -> MEExtensionViewController {
        let controller = ToolbarViewController()
        controller.composeSession = session
        return controller
    }

    // MARK: - Compose Validation

    /// Allows the extension to annotate recipient addresses (e.g., with icons).
    func annotateAddressesForSession(_ session: MEComposeSession) async -> [String: MEAddressAnnotation] {
        return [:]
    }

    /// Called before the message is sent. We allow all messages through.
    func allowMessageSendForSession(_ session: MEComposeSession) async -> MEOutgoingMessageEncodingStatus {
        return MEOutgoingMessageEncodingStatus(
            canSign: false,
            canEncrypt: false,
            securityError: nil,
            addressesFailingEncryption: []
        )
    }
}
