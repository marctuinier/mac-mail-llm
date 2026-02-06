import Foundation

/// Represents the email context extracted from a Mail.app compose session.
/// This model is written by the Mail extension and read by the host app.
struct EmailContextModel: Codable, Identifiable {
    var id: UUID = UUID()

    /// The subject line of the email being replied to (or the new email subject).
    var subject: String

    /// The sender's email address of the original email (empty for new compositions).
    var fromAddress: String

    /// All recipient email addresses.
    var recipientAddresses: [String]

    /// The plain-text body of the original email being replied to.
    var bodyText: String

    /// The HTML body of the original email (if available).
    var bodyHTML: String?

    /// The date the original email was sent.
    var dateReceived: Date?

    /// Whether this is a reply (true) or a new composition (false).
    var isReply: Bool

    /// Timestamp of when this context was created.
    var timestamp: Date = Date()
}
