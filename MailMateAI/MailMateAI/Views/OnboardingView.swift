import SwiftUI

/// First-launch onboarding flow that walks the user through:
/// 1. Welcome screen
/// 2. Entering their Gemini API key
/// 3. Enabling the Mail extension in System Settings
/// 4. Granting Accessibility permission
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep = 0
    @State private var apiKey = ""
    @State private var apiKeySaved = false

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressBar
                .padding(.top, 24)
                .padding(.horizontal, 40)
                .padding(.bottom, 8)

            // Step content -- manual switching instead of TabView to avoid macOS tab chrome
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: apiKeyStep
                case 2: extensionStep
                case 3: accessibilityStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.25), value: currentStep)

            Divider()

            // Navigation buttons
            navigationButtons
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
        }
        .frame(width: 560, height: 500)
        .interactiveDismissDisabled()
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(height: 4)
            }
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

            Text("Welcome to MailMate AI")
                .font(.largeTitle.bold())

            Text("Your intelligent email reply assistant for Mac Mail.\nGenerate professional replies in seconds using AI.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Step 2: API Key

    private var apiKeyStep: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            Text("Connect to Gemini")
                .font(.title.bold())

            Text("MailMate AI uses Google's Gemini API to generate email replies.\nYou'll need a free API key from Google AI Studio.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            VStack(spacing: 14) {
                SecureField("Paste your Gemini API key here", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: 380)

                HStack(spacing: 12) {
                    Link(destination: URL(string: "https://aistudio.google.com/app/apikey")!) {
                        Label("Get API Key", systemImage: "arrow.up.right.square")
                            .font(.subheadline)
                    }

                    if apiKeySaved {
                        Label("Saved!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                            .transition(.opacity)
                    } else if !apiKey.isEmpty {
                        Button("Save Key") {
                            KeychainService.shared.storeAPIKey(apiKey)
                            withAnimation { apiKeySaved = true }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Step 3: Mail Extension

    private var extensionStep: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 36))
                .foregroundStyle(.blue)

            Text("Enable Mail Extension")
                .font(.title.bold())

            Text("To add the AI button to Mail's compose toolbar:")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                instructionRow(number: 1, text: "Click \"Open System Settings\" below")
                instructionRow(number: 2, text: "Under General → Login Items & Extensions")
                instructionRow(number: 3, text: "Find MailMate AI and click the ⓘ info button")
                instructionRow(number: 4, text: "Toggle on the Mail Extensions checkbox")
            }
            .padding(.horizontal, 4)

            HStack(spacing: 12) {
                Button("Open Extensions Settings") {
                    openMailExtensionSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Button("Open Mail Settings") {
                    openMailSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.top, 4)

            Text("You may also need to enable it in Mail → Settings → Extensions.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(.horizontal, 50)
    }

    // MARK: - Step 4: Accessibility

    private var accessibilityStep: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "hand.raised.fill")
                .font(.system(size: 36))
                .foregroundStyle(.purple)

            Text("Auto-Paste Permission")
                .font(.title.bold())

            Text("MailMate AI can automatically paste generated replies\ninto Mail's compose window — no Cmd+V needed.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Text("This requires Accessibility permission.\nClick below to open Privacy settings and add MailMate AI.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Button("Open Accessibility Settings") {
                openAccessibilitySettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 4)

            Text("Optional — you can skip this and paste manually with ⌘V.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding(.horizontal, 50)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack {
            if currentStep > 0 {
                Button("Back") {
                    withAnimation { currentStep -= 1 }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if currentStep < totalSteps - 1 {
                Button("Next") {
                    withAnimation { currentStep += 1 }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Get Started") {
                    appState.completeOnboarding()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Helpers

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.tint, in: Circle())

            Text(text)
                .font(.body)
        }
    }

    private func openMailExtensionSettings() {
        // Open Login Items & Extensions in System Settings
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openMailSettings() {
        // Open Mail.app, then the user can go to Mail > Settings > Extensions
        NSWorkspace.shared.launchApplication("Mail")
    }

    private func openAccessibilitySettings() {
        // Open Privacy > Accessibility in System Settings
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
