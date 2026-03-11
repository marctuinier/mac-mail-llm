import SwiftUI

@main
struct MailMateAIApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        // Main settings window
        WindowGroup("MailMate AI", id: "main") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 600, minHeight: 500)
        }
        .defaultSize(width: 700, height: 600)

        // Compose assistant floating panel (opened via URL scheme)
        WindowGroup("Compose Assistant", id: "compose") {
            ComposeAssistantView()
                .environmentObject(appState)
                .frame(minWidth: 420, minHeight: 500)
        }
        .defaultSize(width: 460, height: 620)
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)

        // Settings window
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

// MARK: - App State

/// Shared application state observable across all views.
@MainActor
final class AppState: ObservableObject {
    @Published var savedPrompts: [SavedPrompt] = []
    @Published var toneSamples: [ToneSample] = []
    @Published var emailContext: EmailContextModel?
    @Published var generatedHTML: String = ""
    @Published var showOnboarding: Bool = false
    @Published var callHistory: [CallRecord] = []

    private let dataService = SharedDataService.shared
    private var pollTimer: Timer?

    init() {
        loadData()
        listenForEmailContextUpdates()
        listenForCallHistoryUpdates()
        startPolling()
        listenForAppActivation()
    }

    func loadData() {
        savedPrompts = dataService.loadSavedPrompts()
        toneSamples = dataService.loadToneSamples()
        emailContext = dataService.readEmailContext()
        showOnboarding = !dataService.onboardingCompleted
        loadCallHistory()
    }

    func savePrompts() {
        try? dataService.saveSavedPrompts(savedPrompts)
    }

    func saveToneSamples() {
        try? dataService.saveToneSamples(toneSamples)
    }

    func refreshEmailContext() {
        emailContext = dataService.readEmailContext()
    }

    func loadCallHistory() {
        callHistory = CallHistoryStore.loadAll().sorted { $0.timestamp > $1.timestamp }
    }

    func clearCallHistory() {
        CallHistoryStore.clear()
        callHistory = []
    }

    func completeOnboarding() {
        dataService.onboardingCompleted = true
        showOnboarding = false
    }

    /// Listen for distributed notifications from the Mail extension
    /// when new email context is available.
    private func listenForEmailContextUpdates() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleEmailContextUpdate),
            name: NSNotification.Name(AppGroupConstants.emailContextUpdatedNotification),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func handleEmailContextUpdate() {
        refreshEmailContext()
    }

    /// Listen for distributed notifications from the Mail extension
    /// when a new call history record is written.
    private func listenForCallHistoryUpdates() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleCallHistoryUpdate),
            name: NSNotification.Name(AppGroupConstants.callHistoryUpdatedNotification),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func handleCallHistoryUpdate() {
        loadCallHistory()
    }

    /// Poll the call history file every 5 seconds so the UI stays
    /// up-to-date even when distributed notifications are deferred.
    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.loadCallHistory() }
        }
    }

    /// Reload everything when the user switches back to the host app.
    private func listenForAppActivation() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.loadCallHistory() }
        }
    }
}
