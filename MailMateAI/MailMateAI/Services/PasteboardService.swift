import AppKit
import Foundation

/// Service for placing rich text (HTML) content on the system pasteboard.
/// Provides the content in multiple formats so Mail.app can paste it with
/// hyperlinks and formatting preserved.
final class PasteboardService {
    static let shared = PasteboardService()

    private init() {}

    /// Place HTML content on the system pasteboard with RTF and plain-text fallbacks.
    /// This ensures that when pasted into Mail.app, hyperlinks and formatting are preserved.
    ///
    /// - Parameter html: The HTML string to place on the pasteboard.
    /// - Throws: If the HTML cannot be converted to attributed string representations.
    func placeOnPasteboard(html: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // Wrap in minimal HTML structure if not already wrapped
        let fullHTML: String
        if html.lowercased().contains("<p>") || html.lowercased().contains("<br") {
            fullHTML = html
        } else {
            fullHTML = "<p>\(html)</p>"
        }

        // Convert HTML to NSAttributedString for RTF and plain-text representations
        guard let htmlData = fullHTML.data(using: .utf8) else {
            throw PasteboardError.encodingFailed
        }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        let attributedString = try NSAttributedString(data: htmlData, options: options, documentAttributes: nil)

        // Generate RTF data from the attributed string
        let rtfData = try attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )

        // Place all three formats on the pasteboard
        // Mail.app will prefer the richest format available
        pasteboard.declareTypes([.html, .rtf, .string], owner: nil)
        pasteboard.setString(fullHTML, forType: .html)
        pasteboard.setData(rtfData, forType: .rtf)
        pasteboard.setString(attributedString.string, forType: .string)
    }

    /// Preview the HTML as an NSAttributedString for rendering in the app.
    ///
    /// - Parameter html: The HTML to render.
    /// - Returns: An NSAttributedString representation.
    func attributedString(from html: String) -> NSAttributedString? {
        guard let data = html.data(using: .utf8) else { return nil }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        return try? NSAttributedString(data: data, options: options, documentAttributes: nil)
    }
}

// MARK: - Errors

enum PasteboardError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode HTML content for the pasteboard."
        }
    }
}
