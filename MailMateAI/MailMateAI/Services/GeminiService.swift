import Foundation

/// Handles communication with the Google Gemini API for generating email replies.
@MainActor
final class GeminiService: ObservableObject {
    static let shared = GeminiService()

    /// The base URL for the Gemini API.
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    /// Published state for UI binding.
    @Published var isGenerating = false
    @Published var streamedResponse = ""
    @Published var error: String?

    /// The conversation history for iterative editing.
    private var conversationHistory: [[String: Any]] = []

    private init() {}

    // MARK: - Public API

    /// Generate an email reply using a saved prompt and email context.
    /// Streams the response back incrementally.
    func generateReply(
        emailContext: EmailContextModel,
        prompt: SavedPrompt,
        customInstruction: String? = nil,
        toneSamples: [ToneSample],
        signature: String,
        model: String
    ) async throws -> String {
        let apiKey = KeychainService.shared.retrieveAPIKey()
        guard let apiKey, !apiKey.isEmpty else {
            throw GeminiError.noAPIKey
        }

        isGenerating = true
        streamedResponse = ""
        error = nil
        conversationHistory = []

        let systemPrompt = buildSystemPrompt(
            emailContext: emailContext,
            prompt: prompt,
            customInstruction: customInstruction,
            toneSamples: toneSamples,
            signature: signature
        )

        let userMessage = buildUserMessage(emailContext: emailContext, prompt: prompt, customInstruction: customInstruction)

        conversationHistory = [
            ["role": "user", "parts": [["text": userMessage]]]
        ]

        let result = try await streamGenerate(
            apiKey: apiKey,
            model: model,
            systemInstruction: systemPrompt,
            contents: conversationHistory
        )

        // Add assistant response to history for follow-up edits
        conversationHistory.append(
            ["role": "model", "parts": [["text": result]]]
        )

        isGenerating = false
        return result
    }

    /// Send an iterative edit request using natural language.
    func editReply(
        instruction: String,
        model: String
    ) async throws -> String {
        let apiKey = KeychainService.shared.retrieveAPIKey()
        guard let apiKey, !apiKey.isEmpty else {
            throw GeminiError.noAPIKey
        }

        isGenerating = true
        streamedResponse = ""
        error = nil

        // Add the edit instruction to conversation history
        conversationHistory.append(
            ["role": "user", "parts": [["text": "Please modify the email reply based on this feedback: \(instruction). Return only the updated email HTML, nothing else."]]]
        )

        let systemEdit = """
        You are an email editing assistant. The user wants to modify the previously generated email reply.
        Apply the requested changes while maintaining the same overall format and tone.
        Return ONLY the complete updated email in HTML format. Do not include any explanation or markdown.
        """

        let result = try await streamGenerate(
            apiKey: apiKey,
            model: model,
            systemInstruction: systemEdit,
            contents: conversationHistory
        )

        // Update history with new response
        conversationHistory.append(
            ["role": "model", "parts": [["text": result]]]
        )

        isGenerating = false
        return result
    }

    /// Reset the conversation history.
    func resetConversation() {
        conversationHistory = []
        streamedResponse = ""
        error = nil
    }

    // MARK: - System Prompt Construction

    private func buildSystemPrompt(
        emailContext: EmailContextModel,
        prompt: SavedPrompt,
        customInstruction: String?,
        toneSamples: [ToneSample],
        signature: String
    ) -> String {
        var parts: [String] = []

        parts.append("""
        You are an expert email reply assistant. Your task is to generate professional email replies
        in HTML format. The reply should be ready to paste directly into an email client.

        IMPORTANT RULES:
        - Return ONLY the email body in HTML format (no <html>, <head>, or <body> tags - just the content).
        - Use <p> tags for paragraphs, <br> for line breaks within paragraphs.
        - Use <a href="URL">text</a> for any hyperlinks.
        - Use <strong> for bold and <em> for italic where appropriate.
        - Do NOT include the subject line or email headers.
        - Do NOT include "Dear [Name]," unless the instruction specifies to.
        - Match the tone and style described below.
        """)

        // Add tone samples if available
        if !toneSamples.isEmpty {
            parts.append("\nTONE REFERENCE - Here are examples of how the user writes emails. Match this style:\n")
            for (index, sample) in toneSamples.prefix(5).enumerated() {
                parts.append("Example \(index + 1) (\(sample.label)):\n\"\"\"\n\(sample.emailText)\n\"\"\"\n")
            }
        }

        // Add links that should be included
        if !prompt.links.isEmpty {
            parts.append("\nLINKS TO INCLUDE in the reply (use these as hyperlinks where contextually appropriate):")
            for link in prompt.links {
                parts.append("- \(link.label): \(link.url)")
            }
        }

        // Add signature
        let sig = prompt.signature ?? signature
        if !sig.isEmpty {
            parts.append("\nSIGNATURE - End the email with this signature:\n\(sig)")
        }

        return parts.joined(separator: "\n")
    }

    private func buildUserMessage(
        emailContext: EmailContextModel,
        prompt: SavedPrompt,
        customInstruction: String?
    ) -> String {
        var message = ""

        if emailContext.isReply {
            message += "I need to reply to the following email:\n\n"
            message += "Subject: \(emailContext.subject)\n"
            message += "From: \(emailContext.fromAddress)\n"
            if let date = emailContext.dateReceived {
                message += "Date: \(date.formatted())\n"
            }
            message += "\nOriginal email body:\n\"\"\"\n\(emailContext.bodyText)\n\"\"\"\n\n"
        } else {
            message += "I need to compose a new email.\n"
            message += "Subject: \(emailContext.subject)\n"
            message += "To: \(emailContext.recipientAddresses.joined(separator: ", "))\n\n"
        }

        // Use custom instruction if provided, otherwise use the saved prompt
        let instruction = customInstruction ?? prompt.instruction
        message += "INSTRUCTION: \(instruction)\n"
        message += "\nGenerate the email reply in HTML format now."

        return message
    }

    // MARK: - Streaming API Call

    private func streamGenerate(
        apiKey: String,
        model: String,
        systemInstruction: String,
        contents: [[String: Any]]
    ) async throws -> String {
        let urlString = "\(baseURL)/\(model):streamGenerateContent?alt=sse&key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": systemInstruction]]
            ],
            "contents": contents,
            "generationConfig": [
                "temperature": 0.7,
                "topP": 0.95,
                "topK": 40,
                "maxOutputTokens": 4096,
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Use URLSession for SSE streaming
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            // Try to read the error body
            var errorBody = ""
            for try await line in asyncBytes.lines {
                errorBody += line
            }
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        var fullResponse = ""

        for try await line in asyncBytes.lines {
            // SSE format: lines starting with "data: " contain JSON
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))

                // Skip empty data or [DONE] signals
                if jsonString.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                if jsonString.contains("[DONE]") { break }

                // Parse the JSON chunk
                if let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first,
                   let content = firstCandidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let text = parts.first?["text"] as? String {
                    fullResponse += text
                    // Update the published property on the main actor
                    streamedResponse = fullResponse
                }
            }
        }

        if fullResponse.isEmpty {
            throw GeminiError.emptyResponse
        }

        return fullResponse
    }
}

// MARK: - Error Types

enum GeminiError: LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Gemini API key configured. Please add your API key in Settings."
        case .invalidURL:
            return "Invalid API URL."
        case .invalidResponse:
            return "Received an invalid response from the Gemini API."
        case .apiError(let statusCode, let message):
            return "API error (\(statusCode)): \(message)"
        case .emptyResponse:
            return "The AI returned an empty response. Please try again."
        }
    }
}
