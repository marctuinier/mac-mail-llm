import SwiftUI

/// The main view of the host app. Shows a home screen with navigation to
/// settings, saved prompts, and quick access to the compose assistant.
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .sheet(isPresented: $appState.showOnboarding) {
            OnboardingView()
                .environmentObject(appState)
        }
        .onOpenURL { url in
            handleURL(url)
        }
    }

    // MARK: - Sidebar

    @State private var selectedTab: SidebarTab? = .prompts

    enum SidebarTab: String, CaseIterable, Identifiable {
        case prompts = "Saved Prompts"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .prompts: return "text.bubble"
            case .settings: return "gear"
            }
        }
    }

    private var sidebar: some View {
        List(SidebarTab.allCases, selection: $selectedTab) { tab in
            Label(tab.rawValue, systemImage: tab.icon)
                .tag(tab)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        .safeAreaInset(edge: .top) {
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                Text("MailMate AI")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .prompts:
            SavedPromptsView()
        case .settings:
            SettingsView()
        case .none:
            Text("Select an item from the sidebar.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - URL Handling

    private func handleURL(_ url: URL) {
        guard url.scheme == AppGroupConstants.urlScheme else { return }

        if url.host == "compose" {
            // Refresh the email context and open the compose assistant window
            appState.refreshEmailContext()
            openComposeWindow()
        }
    }

    private func openComposeWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let existingWindow = NSApp.windows.first(where: { $0.title == "Compose Assistant" }) {
            existingWindow.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "compose")
        }
    }
}
