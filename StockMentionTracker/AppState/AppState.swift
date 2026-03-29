import Foundation
import SwiftUI
import Observation

@Observable
class AppState {
    private let defaults = UserDefaults.standard

    static let githubPATKey = "github_pat"

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

    // MARK: - ETF Category Filters

    var showETFIndex: Bool = UserDefaults.standard.object(forKey: "showETFIndex") == nil
        ? true : UserDefaults.standard.bool(forKey: "showETFIndex") {
        didSet { defaults.set(showETFIndex, forKey: "showETFIndex") }
    }
    var showETFDividend: Bool = UserDefaults.standard.object(forKey: "showETFDividend") == nil
        ? true : UserDefaults.standard.bool(forKey: "showETFDividend") {
        didSet { defaults.set(showETFDividend, forKey: "showETFDividend") }
    }
    var showETFTech: Bool = UserDefaults.standard.object(forKey: "showETFTech") == nil
        ? true : UserDefaults.standard.bool(forKey: "showETFTech") {
        didSet { defaults.set(showETFTech, forKey: "showETFTech") }
    }
    var showETFActive: Bool = UserDefaults.standard.object(forKey: "showETFActive") == nil
        ? true : UserDefaults.standard.bool(forKey: "showETFActive") {
        didSet { defaults.set(showETFActive, forKey: "showETFActive") }
    }
    var showETFBond: Bool = UserDefaults.standard.object(forKey: "showETFBond") == nil
        ? false : UserDefaults.standard.bool(forKey: "showETFBond") {
        didSet { defaults.set(showETFBond, forKey: "showETFBond") }
    }
    var showETFLeverage: Bool = UserDefaults.standard.object(forKey: "showETFLeverage") == nil
        ? false : UserDefaults.standard.bool(forKey: "showETFLeverage") {
        didSet { defaults.set(showETFLeverage, forKey: "showETFLeverage") }
    }

    func isETFVisible(sector: String?) -> Bool {
        guard let sector else { return true }
        switch sector {
        case "ETF・台股指數":  return showETFIndex
        case "ETF・高股息":    return showETFDividend
        case "ETF・科技":      return showETFTech
        case "ETF・主動型":    return showETFActive
        case "ETF・債券":      return showETFBond
        case "ETF・槓桿反向":  return showETFLeverage
        default:
            // Unknown ETF sub-category: show by default
            if sector.hasPrefix("ETF") { return true }
            return true
        }
    }

    // MARK: - Computed

    var hasDataURL: Bool { !dataURL.isEmpty }
    var hasGitHubConfig: Bool { !githubRepo.isEmpty && !githubPAT.isEmpty }
}
