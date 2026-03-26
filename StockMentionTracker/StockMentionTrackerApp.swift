import SwiftUI

@main
struct StockMentionTrackerApp: App {
    @State private var appState = AppState()
    @State private var dataService = DataService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(dataService)
        }
    }
}

// MARK: - Root View

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(DataService.self) private var dataService

    var body: some View {
        Group {
            if appState.hasCompletedOnboarding {
                MainTabView()
                    .task {
                        await dataService.fetchLatest(from: appState.dataURL)
                    }
                    .onReceive(NotificationCenter.default.publisher(
                        for: UIApplication.willEnterForegroundNotification
                    )) { _ in
                        guard appState.hasDataURL else { return }
                        let stale = dataService.lastFetched.map {
                            Date().timeIntervalSince($0) > 1800  // 30 minutes
                        } ?? true
                        if stale {
                            Task { await dataService.fetchLatest(from: appState.dataURL) }
                        }
                    }
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut, value: appState.hasCompletedOnboarding)
    }
}
