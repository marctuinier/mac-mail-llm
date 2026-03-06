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

    init() {
        loadData()
        listenForEmailContextUpdates()
        listenForCallHistoryUpdates()
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
            forName: NSNotification.Name(AppGroupConstants.emailContextUpdatedNotification),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshEmailContext()
        }
    }

    /// Listen for distributed notifications from the Mail extension
    /// when a new call history record is written.
    private func listenForCallHistoryUpdates() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(AppGroupConstants.callHistoryUpdatedNotification),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadCallHistory()
        }
    }
}
