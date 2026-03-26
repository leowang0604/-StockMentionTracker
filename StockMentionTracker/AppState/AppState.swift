import Foundation
import SwiftUI
import Observation

@Observable
class AppState {
    private let defaults = UserDefaults.standard

    static let githubPATKey   = "github_pat"
    static let geminiAPIKeyKey = "gemini_api_key"

    // MARK: - Onboarding

    var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    // MARK: - GitHub Raw URL (for reading latest.json)

    var dataURL: String = UserDefaults.standard.string(forKey: "dataURL") ?? "" {
        didSet { defaults.set(dataURL, forKey: "dataURL") }
    }

    // MARK: - GitHub Repo (for channel management via API, e.g. "username/repo")

    var githubRepo: String = UserDefaults.standard.string(forKey: "githubRepo") ?? "" {
        didSet { defaults.set(githubRepo, forKey: "githubRepo") }
    }

    // MARK: - GitHub Personal Access Token

    var githubPAT: String = KeychainService.shared.get(key: AppState.githubPATKey) ?? "" {
        didSet { KeychainService.shared.set(key: AppState.githubPATKey, value: githubPAT) }
    }

    // MARK: - Time Range Filter (shared across Ranking / Trend / Content tabs)

    var selectedDays: Double = UserDefaults.standard.double(forKey: "selectedDays") == 0
        ? 30
        : UserDefaults.standard.double(forKey: "selectedDays") {
        didSet { defaults.set(selectedDays, forKey: "selectedDays") }
    }

    var cutoffDate: Date {
        Calendar.current.date(byAdding: .day, value: -Int(selectedDays), to: Date()) ?? Date()
    }

    // MARK: - Gemini API Key (for sentiment analysis, optional)

    var geminiAPIKey: String = KeychainService.shared.get(key: AppState.geminiAPIKeyKey) ?? "" {
        didSet { KeychainService.shared.set(key: AppState.geminiAPIKeyKey, value: geminiAPIKey) }
    }

    // MARK: - Computed

    var hasDataURL: Bool { !dataURL.isEmpty }
    var hasGitHubConfig: Bool { !githubRepo.isEmpty && !githubPAT.isEmpty }
}
