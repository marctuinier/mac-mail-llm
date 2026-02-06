import SwiftUI

/// The floating panel that appears when the user clicks the AI button in Mail's compose toolbar.
/// Shows the email context, a prompt input field, saved prompts, and the generated reply.
struct ComposeAssistantView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var gemini = GeminiService.shared

    @State private var userInput = ""
    @State private var selectedPrompt: SavedPrompt?
    @State private var generatedHTML = ""
    @State private var isInEditMode = false
    @State private var showError = false
    @State private var errorMessage = ""

    private let dataService = SharedDataService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header with email context summary
            emailContextHeader

            Divider()

            // Main content area
            ScrollView {
                VStack(spacing: 16) {
                    if generatedHTML.isEmpty && !gemini.isGenerating {
                        promptInputSection
                        savedPromptsSection
                    } else {
                        responseSection
                    }
                }
                .padding()
            }

            Divider()

            // Bottom action bar
            actionBar
        }
        .frame(minWidth: 420)
        .background(.background)
        .onAppear {
            appState.refreshEmailContext()
            checkForExtensionAction()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Email Context Header

    private var emailContextHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let context = appState.emailContext {
                HStack {
                    Image(systemName: context.isReply ? "arrowshape.turn.up.left.fill" : "square.and.pencil")
                        .foregroundStyle(.secondary)
                    Text(context.isReply ? "Replying to email" : "New email")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(context.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if !context.subject.isEmpty {
                    Text(context.subject)
                        .font(.headline)
                        .lineLimit(2)
                }

                if context.isReply && !context.fromAddress.isEmpty {
                    Text("From: \(context.fromAddress)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("No email context available. Open this from a Mail compose window.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    // MARK: - Prompt Input Section

    private var promptInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Compose")
                .font(.title3.bold())

            TextField(
                "What would you like to draft as a reply?",
                text: $userInput,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(3...6)

            if !userInput.isEmpty {
                HStack {
                    Spacer()
                    Button {
                        generateWithCustomInstruction()
                    } label: {
                        Label("Generate", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.emailContext == nil)
                }
            }
        }
    }

    // MARK: - Saved Prompts Section

    private var savedPromptsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved Prompts")
                .font(.title3.bold())

            if appState.savedPrompts.isEmpty {
                Text("No saved prompts yet. Add some in Settings.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(appState.savedPrompts) { prompt in
                    savedPromptRow(prompt)
                }
            }
        }
    }

    private func savedPromptRow(_ prompt: SavedPrompt) -> some View {
        Button {
            selectedPrompt = prompt
            generateWithSavedPrompt(prompt)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(prompt.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(prompt.instruction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            .padding(12)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(appState.emailContext == nil || gemini.isGenerating)
    }

    // MARK: - Response Section

    private var responseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status indicator
            if gemini.isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating reply...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Rendered preview of the generated reply
            if !gemini.streamedResponse.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.title3.bold())

                    RichTextPreview(html: gemini.streamedResponse)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                        .padding(12)
                        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            // Edit mode
            if !gemini.isGenerating && !generatedHTML.isEmpty {
                ChatEditView(
                    generatedHTML: $generatedHTML,
                    onHTMLUpdated: { newHTML in
                        generatedHTML = newHTML
                    }
                )
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack {
            if !generatedHTML.isEmpty {
                Button("Start Over") {
                    resetState()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if !generatedHTML.isEmpty && !gemini.isGenerating {
                Button {
                    insertIntoMail()
                } label: {
                    Label("Insert into Mail", systemImage: "envelope.arrow.triangle.branch")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func generateWithSavedPrompt(_ prompt: SavedPrompt) {
        guard let context = appState.emailContext else { return }

        Task {
            do {
                let result = try await gemini.generateReply(
                    emailContext: context,
                    prompt: prompt,
                    toneSamples: appState.toneSamples,
                    signature: dataService.defaultSignature,
                    model: dataService.geminiModel
                )
                generatedHTML = result
                isInEditMode = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func generateWithCustomInstruction() {
        guard let context = appState.emailContext else { return }

        let prompt = SavedPrompt(
            name: "Custom",
            instruction: userInput
        )

        Task {
            do {
                let result = try await gemini.generateReply(
                    emailContext: context,
                    prompt: prompt,
                    customInstruction: userInput,
                    toneSamples: appState.toneSamples,
                    signature: dataService.defaultSignature,
                    model: dataService.geminiModel
                )
                generatedHTML = result
                isInEditMode = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func insertIntoMail() {
        Task {
            do {
                try await MailBridgeService.shared.insertIntoMail(html: generatedHTML)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func resetState() {
        generatedHTML = ""
        isInEditMode = false
        userInput = ""
        selectedPrompt = nil
        gemini.resetConversation()
    }

    /// Check if the Mail extension passed an action (saved prompt selection or custom instruction).
    private func checkForExtensionAction() {
        let defaults = AppGroupConstants.sharedDefaults
        guard let action = defaults.string(forKey: "compose_action") else { return }

        // Clear the action so it doesn't re-trigger
        defaults.removeObject(forKey: "compose_action")
        defaults.synchronize()

        if action == "saved_prompt",
           let promptId = defaults.string(forKey: "selected_prompt_id") {
            defaults.removeObject(forKey: "selected_prompt_id")
            defaults.synchronize()

            // Find the matching prompt
            if let prompt = appState.savedPrompts.first(where: { $0.id.uuidString == promptId }) {
                selectedPrompt = prompt
                generateWithSavedPrompt(prompt)
            }
        } else if action == "custom",
                  let instruction = defaults.string(forKey: "custom_instruction") {
            defaults.removeObject(forKey: "custom_instruction")
            defaults.synchronize()

            userInput = instruction
            generateWithCustomInstruction()
        }
    }
}

// MARK: - Rich Text Preview

/// Renders HTML content as an attributed string in a native text view.
struct RichTextPreview: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        if let attrStr = PasteboardService.shared.attributedString(from: html) {
            textView.textStorage?.setAttributedString(attrStr)
        } else {
            textView.string = html
        }
    }
}
