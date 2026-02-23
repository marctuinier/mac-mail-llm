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

        let structured = parseStructuredInstruction(instruction)

        let systemPrompt = buildSystemPrompt(
            links: links, signature: signature, toneSamples: toneSamples,
            structured: structured
        )
        lastSystemPrompt = systemPrompt

        let userMessage = buildUserMessage(
            emailContext: emailContext, instruction: instruction,
            isStructured: structured != nil
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
        Apply the requested changes while preserving the emotional tone, empathy, and direct acknowledgment
        of the original sender's concerns. Keep the same human, conversational quality.
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

    // MARK: - Structured Prompt Parsing

    private struct StructuredPrompt {
        var senderName: String?
        var senderTitle: String?
        var senderEmail: String?
        var toneGuidelines: [String] = []
        var resources: [(label: String, url: String)] = []
        var companyStatus: [String: Any] = [:]
        var talkingPoints: [String: Any] = [:]
        var standardReplies: [String: Any] = [:]
        var logicTreeResponses: [String: Any] = [:]
    }

    private func parseStructuredInstruction(_ instruction: String) -> StructuredPrompt? {
        guard let data = instruction.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let knownKeys: Set<String> = [
            "sender_profile", "resources", "company_status",
            "key_talking_points", "standard_replies", "logic_tree_responses"
        ]
        guard !knownKeys.isDisjoint(with: json.keys) else { return nil }

        var s = StructuredPrompt()

        if let profile = json["sender_profile"] as? [String: Any] {
            s.senderName = profile["name"] as? String
            s.senderTitle = profile["title"] as? String
            s.senderEmail = profile["email"] as? String
            s.toneGuidelines = profile["tone_guidelines"] as? [String] ?? []
        }

        if let resources = json["resources"] as? [String: String] {
            for (label, url) in resources {
                let readableLabel = label
                    .replacingOccurrences(of: "_", with: " ")
                    .capitalized
                s.resources.append((readableLabel, url))
            }
        }

        if let status = json["company_status"] as? [String: Any] {
            s.companyStatus = status
        }
        if let tp = json["key_talking_points"] as? [String: Any] {
            s.talkingPoints = tp
        }
        if let sr = json["standard_replies"] as? [String: Any] {
            s.standardReplies = sr
        }
        if let lt = json["logic_tree_responses"] as? [String: Any] {
            s.logicTreeResponses = lt
        }

        return s
    }

    // MARK: - Prompt Construction

    private func buildSystemPrompt(
        links: [(label: String, url: String)],
        signature: String,
        toneSamples: [(label: String, text: String)],
        structured: StructuredPrompt? = nil
    ) -> String {
        var parts: [String] = []

        if let s = structured {
            var identity = "You are an expert email reply assistant writing on behalf of"
            if let name = s.senderName {
                identity += " \(name)"
                if let title = s.senderTitle { identity += ", \(title)" }
            } else {
                identity += " the user"
            }
            identity += "."

            parts.append("""
            \(identity)

            REPLY APPROACH:
            1. Carefully read the original email. Identify the sender's emotional state, specific concerns,
               demands, and questions. Pay close attention to anger, frustration, ultimatums, or desperation.
            2. Begin by directly and empathetically acknowledging how the sender feels. Reference their own
               words or sentiments. If they are angry, acknowledge their anger specifically. If they made a
               demand, state what they demanded before responding to it.
            3. Address EVERY specific point, question, or demand they raised. Do not skip or gloss over
               anything. If you cannot fulfill a request, say so clearly and explain why.
            4. Use the FACTUAL CONTEXT and TALKING POINTS provided below as your source of truth. Do not
               invent facts. Adapt the REPLY TEMPLATES to fit this specific email rather than copying them
               verbatim -- the templates are reference material, not scripts.
            5. Be human, direct, and transparent. Never use corporate jargon or evasive language.
            6. If the sender wrote in a language other than English, reply in that same language unless
               instructed otherwise.

            FORMAT RULES:
            - Return ONLY the email body in HTML format (no <html>, <head>, or <body> tags).
            - Use <p> tags for paragraphs, <br> for line breaks within paragraphs.
            - Use <a href="URL">text</a> for hyperlinks. NEVER paste raw URLs.
            - Do NOT include the subject line or email headers.
            """)

            if !s.toneGuidelines.isEmpty {
                parts.append("\nTONE GUIDELINES:")
                for guideline in s.toneGuidelines {
                    parts.append("- \(guideline)")
                }
            }

            if !s.companyStatus.isEmpty {
                parts.append("\nFACTUAL CONTEXT (company status):")
                parts.append(dictToReadableText(s.companyStatus, indent: 0))
            }

            if !s.talkingPoints.isEmpty {
                parts.append("\nKEY TALKING POINTS (use these as ground truth when addressing the sender's questions):")
                parts.append(dictToReadableText(s.talkingPoints, indent: 0))
            }

            var allLinks = links
            allLinks.append(contentsOf: s.resources)
            if !allLinks.isEmpty {
                parts.append("\nLINKS TO INCLUDE (use as hyperlinks where contextually appropriate):")
                for link in allLinks {
                    parts.append("- \(link.label): \(link.url)")
                }
            }

            if !s.standardReplies.isEmpty {
                parts.append("\nREPLY TEMPLATES (adapt to this specific email -- do not copy verbatim):")
                parts.append(dictToReadableText(s.standardReplies, indent: 0))
            }

            if !s.logicTreeResponses.isEmpty {
                parts.append("\nSITUATION-SPECIFIC TEMPLATES (use the most relevant one as a starting point):")
                parts.append(dictToReadableText(s.logicTreeResponses, indent: 0))
            }

        } else {
            parts.append("""
            You are an expert email reply assistant. Your task is to generate thoughtful, human email replies
            in HTML format. The reply should be ready to paste directly into an email client.

            REPLY APPROACH:
            1. First, carefully read the original email to understand the sender's emotional state, specific
               concerns, demands, and questions. Pay attention to frustration, urgency, anger, gratitude, etc.
            2. Begin the reply by directly acknowledging how the sender feels and what they specifically said.
               Reference their own words or sentiments when appropriate. Show genuine empathy before anything else.
            3. Address each specific point, question, or demand they raised -- do not skip or gloss over anything.
               If you cannot fulfill a request, say so clearly and explain why, rather than simply ignoring it.
            4. Be human and conversational. Write as a real person would, not as a corporate template. Adapt your
               tone to match the situation: warm for friendly emails, compassionate for angry ones, direct for
               business ones.
            5. If the sender wrote in a language other than English, reply in that same language unless the user's
               instruction specifies otherwise.

            FORMAT RULES:
            - Return ONLY the email body in HTML format (no <html>, <head>, or <body> tags).
            - Use <p> tags for paragraphs, <br> for line breaks within paragraphs.
            - Use <a href="URL">text</a> for any hyperlinks.
            - Do NOT include the subject line or email headers.
            """)

            if !links.isEmpty {
                parts.append("\nLINKS TO INCLUDE (use as hyperlinks where contextually appropriate):")
                for link in links {
                    parts.append("- \(link.label): \(link.url)")
                }
            }
        }

        if !toneSamples.isEmpty {
            parts.append("\nTONE REFERENCE - Match this writing style:\n")
            for (i, sample) in toneSamples.prefix(5).enumerated() {
                parts.append("Example \(i + 1) (\(sample.label)):\n\"\"\"\n\(sample.text)\n\"\"\"\n")
            }
        }

        if !signature.isEmpty {
            parts.append("\nSIGNATURE - End the email with:\n\(signature)")
        }

        return parts.joined(separator: "\n")
    }

    /// Recursively converts a dictionary to human-readable indented text for the system prompt.
    private func dictToReadableText(_ dict: [String: Any], indent: Int) -> String {
        let prefix = String(repeating: "  ", count: indent)
        var lines: [String] = []
        for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
            let label = key.replacingOccurrences(of: "_", with: " ").capitalized
            if let nested = value as? [String: Any] {
                lines.append("\(prefix)[\(label)]")
                lines.append(dictToReadableText(nested, indent: indent + 1))
            } else if let array = value as? [Any] {
                lines.append("\(prefix)\(label):")
                for item in array {
                    if let str = item as? String {
                        lines.append("\(prefix)  - \(str)")
                    } else if let nested = item as? [String: Any] {
                        lines.append(dictToReadableText(nested, indent: indent + 1))
                    }
                }
            } else {
                lines.append("\(prefix)\(label): \(value)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func buildUserMessage(emailContext: [String: Any], instruction: String, isStructured: Bool = false) -> String {
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
                message += "\n(Original email body not available -- compose a contextually appropriate reply based on the subject and instruction.)\n\n"
            }
        } else {
            message += "I need to compose a new email.\n"
            message += "Subject: \(subject)\n"
            if !recipients.isEmpty {
                message += "To: \(recipients.joined(separator: ", "))\n"
            }
            message += "\n"
        }

        if isStructured {
            message += """
            Using the sender profile, factual context, talking points, and reply templates provided \
            in your system instructions, compose a reply to the email above. Carefully identify which \
            situation-specific template is most relevant, then adapt it to directly address this specific \
            sender's emotions, concerns, and demands. Do not copy a template verbatim -- personalize it \
            to acknowledge exactly what this person said and how they feel.
            """
        } else {
            message += "INSTRUCTION: \(instruction)\n"
        }

        message += "\n\nGenerate the email reply in HTML format now."

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
