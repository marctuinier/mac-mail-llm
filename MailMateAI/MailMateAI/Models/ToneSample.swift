import Foundation

/// A sample email that represents the user's writing tone and style.
/// These are provided as few-shot examples to the AI so it can mimic the user's voice.
struct ToneSample: Codable, Identifiable, Hashable {
    /// Unique identifier.
    var id: UUID

    /// A short label describing this sample (e.g., "Client follow-up" or "Casual reply").
    var label: String

    /// The full text of the sample email.
    var emailText: String

    /// When this sample was added.
    var addedAt: Date

    init(
        id: UUID = UUID(),
        label: String,
        emailText: String,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.emailText = emailText
        self.addedAt = addedAt
    }
}
