import SwiftUI

/// Full CRUD view for managing saved prompts.
/// Accessible from the main app's sidebar.
struct SavedPromptsView: View {
    @EnvironmentObject var appState: AppState

    @State private var selectedPromptID: UUID?
    @State private var isEditing = false
    @State private var editingPrompt: SavedPrompt?
    @State private var showDeleteConfirmation = false
    @State private var promptToDelete: SavedPrompt?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Saved Prompts")
                    .font(.title2.bold())
                Spacer()
                Button {
                    createNewPrompt()
                } label: {
                    Label("New Prompt", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()

            Divider()

            if appState.savedPrompts.isEmpty {
                emptyState
            } else {
                promptList
            }
        }
        .sheet(item: $editingPrompt) { prompt in
            PromptEditorSheet(
                prompt: prompt,
                isNew: !appState.savedPrompts.contains(where: { $0.id == prompt.id }),
                onSave: { updatedPrompt in
                    savePrompt(updatedPrompt)
                }
            )
        }
        .alert("Delete Prompt?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let prompt = promptToDelete {
                    deletePrompt(prompt)
                }
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "text.bubble")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Saved Prompts")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Create reusable prompt templates for common email replies.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Create Your First Prompt") {
                createNewPrompt()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
    }

    // MARK: - Prompt List

    private var promptList: some View {
        List(selection: $selectedPromptID) {
            ForEach(appState.savedPrompts) { prompt in
                promptRow(prompt)
                    .tag(prompt.id)
            }
        }
        .listStyle(.inset)
    }

    private func promptRow(_ prompt: SavedPrompt) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(prompt.name)
                    .font(.body.weight(.semibold))
                Spacer()

                Button {
                    editingPrompt = prompt
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)

                Button {
                    promptToDelete = prompt
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            }

            Text(prompt.instruction)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if !prompt.links.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.caption2)
                    Text("\(prompt.links.count) link\(prompt.links.count == 1 ? "" : "s")")
                        .font(.caption)
                }
                .foregroundStyle(.tint)
            }

            if let sig = prompt.signature, !sig.isEmpty {
                Text("Signature: \(sig)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func createNewPrompt() {
        editingPrompt = SavedPrompt(
            name: "",
            instruction: ""
        )
    }

    private func savePrompt(_ prompt: SavedPrompt) {
        if let index = appState.savedPrompts.firstIndex(where: { $0.id == prompt.id }) {
            appState.savedPrompts[index] = prompt
        } else {
            appState.savedPrompts.append(prompt)
        }
        appState.savePrompts()
    }

    private func deletePrompt(_ prompt: SavedPrompt) {
        appState.savedPrompts.removeAll { $0.id == prompt.id }
        appState.savePrompts()
    }
}

// MARK: - Prompt Editor Sheet

struct PromptEditorSheet: View {
    @State var prompt: SavedPrompt
    let isNew: Bool
    let onSave: (SavedPrompt) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isNew ? "New Prompt" : "Edit Prompt")
                    .font(.title3.bold())
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                Button("Save") {
                    prompt.modifiedAt = Date()
                    onSave(prompt)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(prompt.name.isEmpty || prompt.instruction.isEmpty)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Name
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name")
                            .font(.subheadline.weight(.medium))
                        TextField("e.g., Partnership Inquiry Reply", text: $prompt.name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Instruction
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Instruction")
                            .font(.subheadline.weight(.medium))
                        TextEditor(text: $prompt.instruction)
                            .font(.body)
                            .frame(minHeight: 100)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }

                    // Links
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Links")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Button {
                                prompt.links.append(PromptLink(label: "", url: ""))
                            } label: {
                                Label("Add Link", systemImage: "plus")
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }

                        ForEach(Array(prompt.links.enumerated()), id: \.element.id) { index, link in
                            HStack(spacing: 8) {
                                TextField("Label", text: $prompt.links[index].label)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 160)
                                TextField("URL", text: $prompt.links[index].url)
                                    .textFieldStyle(.roundedBorder)
                                Button {
                                    prompt.links.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    // Signature
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Signature Override (optional)")
                            .font(.subheadline.weight(.medium))
                        TextField("e.g., Best regards,\\nYour Name", text: Binding(
                            get: { prompt.signature ?? "" },
                            set: { prompt.signature = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        Text("Leave empty to use the default signature from Settings.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding()
            }
        }
        .frame(width: 520, height: 520)
    }
}
