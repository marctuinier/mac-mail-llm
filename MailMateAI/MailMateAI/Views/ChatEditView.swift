import SwiftUI

/// A conversational edit interface that lets the user refine the generated email reply
/// using natural language. After a reply is generated, this view replaces the prompt field.
struct ChatEditView: View {
    @Binding var generatedHTML: String
    var onHTMLUpdated: (String) -> Void

    @StateObject private var gemini = GeminiService.shared
    @State private var editInstruction = ""
    @State private var editHistory: [EditEntry] = []
    @State private var showError = false
    @State private var errorMessage = ""

    private let dataService = SharedDataService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Refine")
                .font(.title3.bold())

            // Edit history
            if !editHistory.isEmpty {
                ForEach(editHistory) { entry in
                    editEntryRow(entry)
                }
            }

            // Edit input
            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    "Is there anything you'd like to edit?",
                    text: $editInstruction,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit {
                    submitEdit()
                }

                Button {
                    submitEdit()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .disabled(editInstruction.isEmpty || gemini.isGenerating)
            }

            if gemini.isGenerating {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Updating...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Edit Entry Row

    private func editEntryRow(_ entry: EditEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // User's instruction
            HStack {
                Spacer()
                Text(entry.instruction)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            }

            // AI's confirmation
            HStack {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.tint)
                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func submitEdit() {
        let instruction = editInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }

        let currentInstruction = instruction
        editInstruction = ""

        Task {
            do {
                let updatedHTML = try await gemini.editReply(
                    instruction: currentInstruction,
                    model: dataService.geminiModel
                )

                generatedHTML = updatedHTML
                onHTMLUpdated(updatedHTML)

                editHistory.append(EditEntry(
                    instruction: currentInstruction,
                    summary: "Updated the reply based on your feedback."
                ))
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Edit Entry Model

struct EditEntry: Identifiable {
    let id = UUID()
    let instruction: String
    let summary: String
}
