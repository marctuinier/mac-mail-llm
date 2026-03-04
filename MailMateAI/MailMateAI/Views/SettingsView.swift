import SwiftUI

/// Settings view for configuring the API key, Gemini model, signature, and tone samples.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @State private var apiKey: String = ""
    @State private var apiKeyMasked: String = ""
    @State private var showAPIKey = false
    @State private var geminiModel: String = "gemini-2.5-pro"
    @State private var defaultSignature: String = ""
    @State private var showSaveConfirmation = false
    @State private var newToneLabel = ""
    @State private var newToneText = ""
    @State private var showAddToneSample = false

    private let availableModels = [
        "gemini-3.1-flash-lite",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.0-flash",
        "gemini-2.0-flash-lite",
    ]

    private let dataService = SharedDataService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.title2.bold())

                apiKeySection
                modelSection
                signatureSection
                toneSamplesSection
                accessibilitySection
            }
            .padding(24)
        }
        .onAppear {
            loadSettings()
        }
        .alert("Settings Saved", isPresented: $showSaveConfirmation) {
            Button("OK") {}
        }
    }

    // MARK: - API Key Section

    private var apiKeySection: some View {
        GroupBox("Gemini API Key") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your API key is stored securely in the macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    if showAPIKey {
                        TextField("Enter your Gemini API key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("Enter your Gemini API key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        showAPIKey.toggle()
                    } label: {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                HStack {
                    if KeychainService.shared.hasAPIKey {
                        Label("API key is configured", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Label("No API key configured", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Spacer()

                    Button("Save Key") {
                        saveAPIKey()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(apiKey.isEmpty)

                    Link("Get API Key", destination: URL(string: "https://aistudio.google.com/app/apikey")!)
                        .controlSize(.small)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Model Section

    private var modelSection: some View {
        GroupBox("AI Model") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Gemini Model", selection: $geminiModel) {
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: geminiModel) { _, newValue in
                    dataService.geminiModel = newValue
                }

                Text("Pro models produce higher-quality replies but are slower. Flash models are faster and cheaper. 3.1 Flash-Lite is the fastest and most cost-efficient option.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    // MARK: - Signature Section

    private var signatureSection: some View {
        GroupBox("Default Signature") {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $defaultSignature)
                    .font(.body)
                    .frame(height: 60)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .onChange(of: defaultSignature) { _, newValue in
                        dataService.defaultSignature = newValue
                    }

                Text("Appended to all generated replies unless overridden by a saved prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    // MARK: - Tone Samples Section

    private var toneSamplesSection: some View {
        GroupBox("Tone of Voice Samples") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Paste examples of emails you've written so the AI can match your style.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if appState.toneSamples.isEmpty {
                    Text("No tone samples added yet.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(appState.toneSamples) { sample in
                        toneSampleRow(sample)
                    }
                }

                Button {
                    showAddToneSample = true
                } label: {
                    Label("Add Tone Sample", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .sheet(isPresented: $showAddToneSample) {
                    addToneSampleSheet
                }
            }
            .padding(8)
        }
    }

    private func toneSampleRow(_ sample: ToneSample) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(sample.label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    removeToneSample(sample)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            }
            Text(sample.emailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(8)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private var addToneSampleSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Add Tone Sample")
                    .font(.title3.bold())
                Spacer()
                Button("Cancel") { showAddToneSample = false }
                    .buttonStyle(.bordered)
                Button("Add") {
                    addToneSample()
                    showAddToneSample = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newToneLabel.isEmpty || newToneText.isEmpty)
            }

            TextField("Label (e.g., Client follow-up)", text: $newToneLabel)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                Text("Paste an email you've written:")
                    .font(.subheadline)
                TextEditor(text: $newToneText)
                    .font(.body)
                    .frame(minHeight: 150)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding()
        .frame(width: 480, height: 350)
    }

    // MARK: - Accessibility Section

    private var accessibilitySection: some View {
        GroupBox("Accessibility Permission") {
            VStack(alignment: .leading, spacing: 8) {
                Text("MailMate AI needs Accessibility permission to paste generated replies into Mail.app compose windows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    if MailBridgeService.shared.checkAccessibilityPermission() {
                        Label("Accessibility permission granted", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Label("Accessibility permission not granted", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Spacer()

                    Button("Open Accessibility Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Actions

    private func loadSettings() {
        if let existingKey = KeychainService.shared.retrieveAPIKey() {
            apiKey = existingKey
        }
        geminiModel = dataService.geminiModel
        defaultSignature = dataService.defaultSignature
    }

    private func saveAPIKey() {
        KeychainService.shared.storeAPIKey(apiKey)
        showSaveConfirmation = true
    }

    private func addToneSample() {
        let sample = ToneSample(
            label: newToneLabel,
            emailText: newToneText
        )
        appState.toneSamples.append(sample)
        appState.saveToneSamples()
        newToneLabel = ""
        newToneText = ""
    }

    private func removeToneSample(_ sample: ToneSample) {
        appState.toneSamples.removeAll { $0.id == sample.id }
        appState.saveToneSamples()
    }
}
