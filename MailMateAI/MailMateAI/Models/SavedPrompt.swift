import Foundation

/// A reusable prompt template that can be saved and applied to email replies.
struct SavedPrompt: Codable, Identifiable, Hashable {
    /// Unique identifier for this prompt.
    var id: UUID

    /// A human-readable name for the prompt (e.g., "Partnership Inquiry Reply").
    var name: String

    /// The instruction text sent to the AI model describing how to reply.
    var instruction: String

    /// Links that should be included in the generated reply.
    var links: [PromptLink]

    /// An optional signature to append to the reply.
    var signature: String?

    /// When this prompt was created.
    var createdAt: Date

    /// When this prompt was last modified.
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        instruction: String,
        links: [PromptLink] = [],
        signature: String? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.instruction = instruction
        self.links = links
        self.signature = signature
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

/// A hyperlink to be included in generated email replies.
struct PromptLink: Codable, Identifiable, Hashable {
    var id: UUID = UUID()

    /// The display text for the link.
    var label: String

    /// The URL the link points to.
    var url: String
}
