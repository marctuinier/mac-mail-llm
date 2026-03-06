import SwiftUI

/// Displays a table of past AI generation/refinement calls with status, date,
/// model, token usage, and estimated cost. Tapping a row opens the detail view.
struct CallHistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedRecord: CallRecord?
    @State private var showClearConfirmation = false

    var body: some View {
        if let record = selectedRecord {
            CallDetailView(record: record) {
                selectedRecord = nil
            }
        } else {
            mainList
        }
    }

    // MARK: - Main List

    private var mainList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Call History")
                    .font(.title2.bold())
                Spacer()
                if !appState.callHistory.isEmpty {
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Label("Clear History", systemImage: "trash")
                    }
                    .controlSize(.small)
                }
            }
            .padding()

            Divider()

            if appState.callHistory.isEmpty {
                emptyState
            } else {
                historyTable
            }
        }
        .alert("Clear Call History?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                appState.clearCallHistory()
            }
        } message: {
            Text("This will permanently delete all call history records.")
        }
        .onAppear {
            appState.loadCallHistory()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Calls Yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Generation and refinement calls from the Mail extension will appear here.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer()
        }
        .padding()
    }

    // MARK: - History Table

    private var historyTable: some View {
        List(appState.callHistory) { record in
            historyRow(record)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedRecord = record
                }
        }
        .listStyle(.inset)
    }

    private func historyRow(_ record: CallRecord) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(record.status == .success ? Color.green : Color.red)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(record.isRefine ? "Refinement" : "Generation")
                        .font(.body.weight(.semibold))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(record.model)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(record.inputSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(record.timestamp, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(record.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .trailing, spacing: 2) {
                if let tokens = record.totalTokens {
                    Text(Self.formatTokens(tokens))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let cost = record.estimatedCostUSD {
                    Text(Self.formatCost(cost))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tint)
                }
            }
            .frame(minWidth: 72, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Formatting

    static func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM tok", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK tok", Double(count) / 1_000.0)
        }
        return "\(count) tok"
    }

    static func formatCost(_ cost: Double) -> String {
        if cost < 0.001 {
            return "< $0.001"
        }
        return String(format: "$%.4f", cost)
    }
}
