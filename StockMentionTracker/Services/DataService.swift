import Foundation

@MainActor
@Observable
class DataService {
    static let shared = DataService()

    var scanResult: ScanResult = .empty
    var isLoading = false
    var errorMessage: String?
    var lastFetched: Date?

    private let cacheURL: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("latest_scan.json")
    }()

    private init() {
        loadFromCache()
    }

    func fetchLatest(from urlString: String) async {
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            errorMessage = "GitHub Raw URL 未設定"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let result = try JSONDecoder().decode(ScanResult.self, from: data)
            scanResult = result
            lastFetched = Date()
            try? data.write(to: cacheURL)
        } catch {
            errorMessage = "載入失敗：\(error.localizedDescription)"
        }

        isLoading = false
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheURL)
        scanResult = .empty
        lastFetched = nil
    }

    private func loadFromCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let result = try? JSONDecoder().decode(ScanResult.self, from: data) else { return }
        scanResult = result
    }
}
