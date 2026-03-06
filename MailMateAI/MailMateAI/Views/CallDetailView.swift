import SwiftUI

/// Detail view for a single call history record, showing full metadata,
/// instruction/prompt, AI thinking, and generated output.
struct CallDetailView: View {
    let record: CallRecord
    let onBack: () -> Void

    @State private var showInstruction = true
    @State private var showThinking = false
    @State private var showOutput = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    metadataCard
                    instructionSection
                    if record.thinkingText != nil {
                        thinkingSection
                    }
                    if record.outputText != nil {
                        outputSection
                    }
                    if let error = record.errorMessage {
                        errorSection(error)
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                onBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(record.status == .success ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(record.isRefine ? "Refinement" : "Generation")
                    .font(.headline)
            }

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.instruction, forType: .string)
            } label: {
                Label("Copy Instruction", systemImage: "doc.on.doc")
            }
            .controlSize(.small)
            .help("Copy the instruction to clipboard for retry")
        }
        .padding()
    }

    // MARK: - Metadata Card

    private var metadataCard: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading),
            ], spacing: 12) {
                metadataItem(label: "Date", value: formatted(record.timestamp))
                metadataItem(label: "Model", value: record.model)
                metadataItem(label: "Type", value: record.isRefine ? "Refinement" : "Generation")
                metadataItem(label: "Status", value: record.status == .success ? "Success" : "Failed")

                if let tokens = record.totalTokens {
                    metadataItem(label: "Total Tokens", value: CallHistoryView.formatTokens(tokens))
                }
                if let prompt = record.promptTokens {
                    metadataItem(label: "Input Tokens", value: "\(prompt)")
                }
                if let candidate = record.candidateTokens {
                    metadataItem(label: "Output Tokens", value: "\(candidate)")
                }
                if let thought = record.thoughtTokens {
                    metadataItem(label: "Thinking Tokens", value: "\(thought)")
                }
                if let cost = record.estimatedCostUSD {
                    metadataItem(label: "Est. Cost", value: CallHistoryView.formatCost(cost))
                }
                if let duration = record.durationSeconds {
                    metadataItem(label: "Duration", value: String(format: "%.1fs", duration))
                }
            }
        }
        .padding()
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func metadataItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.callout.monospacedDigit())
        }
    }

    // MARK: - Instruction

    private var instructionSection: some View {
        expandableSection(title: "Instruction / Prompt", isExpanded: $showInstruction) {
            Text(record.instruction)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Thinking

    private var thinkingSection: some View {
        expandableSection(title: "AI Thinking", isExpanded: $showThinking) {
            if let thinking = record.thinkingText {
                Text(thinking)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Output

    private var outputSection: some View {
        expandableSection(title: "Generated Output", isExpanded: $showOutput) {
            if let output = record.outputText {
                Text(output)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Error

    private func errorSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Helpers

    private func expandableSection<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                content()
            }
        }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
