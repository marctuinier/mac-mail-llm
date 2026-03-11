import MailKit
import Foundation

/// The principal class for the Mail compose extension.
/// Mail.app instantiates this handler whenever a compose window is opened.
class ComposeSessionHandler: NSObject, MEComposeSessionHandler {

    // MARK: - Session Lifecycle

    /// Called when a new compose session begins (user opens a compose window).
    func mailComposeSessionDidBegin(_ session: MEComposeSession) {
        let mgr = GenerationManager.manager(for: session)

        let origMsg = session.composeContext.originalMessage
        if let rawData = origMsg?.rawData {
            mgr.cachedOriginalRawData = rawData
        }

        FlowLogger.log(step: "session_begin", data: [
            "sessionID": session.composeContext.contextID.uuidString,
            "subject": session.mailMessage.subject,
            "action": String(describing: session.composeContext.action),
            "hasOriginalMessage": origMsg != nil,
            "hasRawData": origMsg?.rawData != nil,
            "rawDataSize": origMsg?.rawData?.count ?? 0,
            "composeHasRawData": session.mailMessage.rawData != nil,
        ])
    }

    /// Called when the compose session ends (window is closed or email is sent).
    func mailComposeSessionDidEnd(_ session: MEComposeSession) {
        GenerationManager.removeManager(for: session)
    }

    // MARK: - Toolbar View Controller

    /// Returns a view controller that Mail.app embeds in the compose toolbar.
    func viewController(for session: MEComposeSession) -> MEExtensionViewController {
        let controller = ToolbarViewController()
        controller.composeSession = session
        return controller
    }

    // MARK: - Compose Validation

    func annotateAddressesForSession(_ session: MEComposeSession) async -> [String: MEAddressAnnotation] {
        return [:]
    }

    func allowMessageSendForSession(_ session: MEComposeSession) async -> MEOutgoingMessageEncodingStatus {
        return MEOutgoingMessageEncodingStatus(
            canSign: false,
            canEncrypt: false,
            securityError: nil,
            addressesFailingEncryption: []
        )
    }
}
