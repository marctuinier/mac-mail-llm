import MailKit

/// The principal class of the Mail extension.
/// Conforms to `MEExtension` and provides the compose session handler.
class MailExtensionPrincipal: NSObject, MEExtension {

    func handler(for session: MEComposeSession) -> MEComposeSessionHandler {
        return ComposeSessionHandler()
    }
}
