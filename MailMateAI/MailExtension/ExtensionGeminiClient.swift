import Foundation

/// A lightweight Gemini API client for the Mail extension.
/// Does not depend on the host app's GeminiService or any SwiftUI.
final class ExtensionGeminiClient {
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    private var conversationHistory: [[String: Any]] = []
    private var lastSystemPrompt: String = ""

    /// Called incrementally as tokens stream in.
    var onToken: ((String) -> Void)?

    /// Number of messages in conversation history (for debugging).
    var conversationHistoryCount: Int { conversationHistory.count }

    // MARK: - Public API

    func generateReply(
        apiKey: String,
        model: String,
        emailContext: [String: Any],
        promptName: String,
        instruction: String,
        links: [(label: String, url: String)],
        signature: String,
        toneSamples: [(label: String, text: String)]
    ) async throws -> String {
        conversationHistory = []

        let systemPrompt = buildSystemPrompt(
            links: links, signature: signature, toneSamples: toneSamples
        )
        lastSystemPrompt = systemPrompt

        let userMessage = buildUserMessage(
            emailContext: emailContext, instruction: instruction
        )

        conversationHistory = [
            ["role": "user", "parts": [["text": userMessage]]]
        ]

        let result = try await streamGenerate(
            apiKey: apiKey, model: model,
            systemInstruction: systemPrompt,
            contents: conversationHistory
        )

        conversationHistory.append(
            ["role": "model", "parts": [["text": result]]]
        )

        return result
    }

    func editReply(apiKey: String, model: String, instruction: String) async throws -> String {
        conversationHistory.append(
            ["role": "user", "parts": [["text": "Please modify the email reply based on this feedback: \(instruction). Return only the updated email HTML, nothing else."]]]
        )

        let systemEdit = """
        You are an email editing assistant. The user wants to modify the previously generated email reply.
        Apply the requested changes while maintaining the same overall format and tone.
        Return ONLY the complete updated email in HTML format. Do not include any explanation or markdown.
        """

        let result = try await streamGenerate(
            apiKey: apiKey, model: model,
            systemInstruction: systemEdit,
            contents: conversationHistory
        )

        conversationHistory.append(
            ["role": "model", "parts": [["text": result]]]
        )

        return result
    }

    func reset() {
        conversationHistory = []
        lastSystemPrompt = ""
    }

    // MARK: - Prompt Construction

    private func buildSystemPrompt(
        links: [(label: String, url: String)],
        signature: String,
        toneSamples: [(label: String, text: String)]
    ) -> String {
        var parts: [String] = []

        parts.append("""
        You are an expert email reply assistant. Your task is to generate professional email replies
        in HTML format. The reply should be ready to paste directly into an email client.

        IMPORTANT RULES:
        - Return ONLY the email body in HTML format (no <html>, <head>, or <body> tags - just the content).
        - Use <p> tags for paragraphs, <br> for line breaks within paragraphs.
        - Use <a href="URL">text</a> for any hyperlinks.
        - Do NOT include the subject line or email headers.
        - Match the tone and style described below.
        """)

        if !toneSamples.isEmpty {
            parts.append("\nTONE REFERENCE - Match this writing style:\n")
            for (i, sample) in toneSamples.prefix(5).enumerated() {
                parts.append("Example \(i + 1) (\(sample.label)):\n\"\"\"\n\(sample.text)\n\"\"\"\n")
            }
        }

        if !links.isEmpty {
            parts.append("\nLINKS TO INCLUDE (use as hyperlinks where contextually appropriate):")
            for link in links {
                parts.append("- \(link.label): \(link.url)")
            }
        }

        if !signature.isEmpty {
            parts.append("\nSIGNATURE - End the email with:\n\(signature)")
        }

        return parts.joined(separator: "\n")
    }

    private func buildUserMessage(emailContext: [String: Any], instruction: String) -> String {
        let subject = emailContext["subject"] as? String ?? ""
        let from = emailContext["fromAddress"] as? String ?? ""
        let body = emailContext["bodyText"] as? String ?? ""
        let isReply = emailContext["isReply"] as? Bool ?? false
        let recipients = emailContext["recipientAddresses"] as? [String] ?? []
        let originalFrom = emailContext["originalFrom"] as? String ?? ""

        var message = ""

        if isReply {
            message += "I need to reply to the following email:\n\n"
            message += "Subject: \(subject)\n"
            if !originalFrom.isEmpty {
                message += "Original sender: \(originalFrom)\n"
            }
            message += "My email: \(from)\n"
            if !recipients.isEmpty {
                message += "To: \(recipients.joined(separator: ", "))\n"
            }
            if !body.isEmpty {
                message += "\nOriginal email body:\n\"\"\"\n\(body)\n\"\"\"\n\n"
            } else {
                message += "\n(Original email body not available — compose a contextually appropriate reply based on the subject and instruction.)\n\n"
            }
        } else {
            message += "I need to compose a new email.\n"
            message += "Subject: \(subject)\n"
            if !recipients.isEmpty {
                message += "To: \(recipients.joined(separator: ", "))\n"
            }
            message += "\n"
        }

        message += "INSTRUCTION: \(instruction)\n"
        message += "\nGenerate the email reply in HTML format now."

        return message
    }

    // MARK: - Streaming API

    private func streamGenerate(
        apiKey: String, model: String,
        systemInstruction: String, contents: [[String: Any]]
    ) async throws -> String {
        let urlString = "\(baseURL)/\(model):streamGenerateContent?alt=sse&key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "GeminiClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": systemInstruction]]],
            "contents": contents,
            "generationConfig": [
                "temperature": 0.7,
                "topP": 0.95,
                "topK": 40,
                "maxOutputTokens": 4096,
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "GeminiClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        if httpResponse.statusCode != 200 {
            var errorBody = ""
            for try await line in asyncBytes.lines { errorBody += line }
            throw NSError(domain: "GeminiClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API error (\(httpResponse.statusCode)): \(errorBody.prefix(200))"])
        }

        var fullResponse = ""

        for try await line in asyncBytes.lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                if jsonString.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                if jsonString.contains("[DONE]") { break }

                if let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   let content = candidates.first?["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let text = parts.first?["text"] as? String {
                    fullResponse += text
                    onToken?(fullResponse)
                }
            }
        }

        if fullResponse.isEmpty {
            throw NSError(domain: "GeminiClient", code: -3, userInfo: [NSLocalizedDescriptionKey: "Empty response from AI"])
        }

        return Self.stripCodeFences(fullResponse)
    }

    /// Strip markdown code fences (```html ... ```) that Gemini often wraps around HTML output.
    private static func stripCodeFences(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove opening fence: ```html or ```HTML or just ```
        if result.hasPrefix("```") {
            if let newlineIdx = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: newlineIdx)...])
            }
        }
        // Remove closing fence
        if result.hasSuffix("```") {
            result = String(result.dropLast(3))
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
