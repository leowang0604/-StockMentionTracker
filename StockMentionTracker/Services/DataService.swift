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
        guard !urlString.isEmpty,
              let baseURL = URL(string: urlString),
              let url = freshURL(from: baseURL) else {
            errorMessage = "GitHub Raw URL 未設定"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 30
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")

            let (data, response) = try await URLSession.shared.data(for: request)
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

    // MARK: - Channel queries

    func stocksByChannel(_ channelName: String, cutoff: Date) -> [StockEntry] {
        scanResult.stocksRanking.compactMap { stock -> StockEntry? in
            let ctxs = stock.contexts.filter {
                $0.channel == channelName && ($0.parsedDate ?? .distantPast) >= cutoff
            }
            guard !ctxs.isEmpty else { return nil }
            return StockEntry(code: stock.code, name: stock.name,
                              market: stock.market, sector: stock.sector,
                              totalMentions: ctxs.count, contexts: ctxs,
                              sentimentScore: nil, daily: nil)
        }.sorted { $0.totalMentions > $1.totalMentions }
    }

    func episodesByChannel(_ channelName: String, cutoff: Date) -> [VideoScanned] {
        scanResult.videosScanned
            .filter { $0.channel == channelName && ($0.parsedDate ?? .distantPast) >= cutoff }
            .sorted { ($0.parsedDate ?? .distantPast) > ($1.parsedDate ?? .distantPast) }
    }

    func stockEntries(for video: VideoScanned) -> [StockEntry] {
        scanResult.stocksRanking.compactMap { stock -> StockEntry? in
            let ctxs = stock.contexts.filter { $0.video == video.title }
            guard !ctxs.isEmpty else { return nil }
            return StockEntry(code: stock.code, name: stock.name,
                              market: stock.market, sector: stock.sector,
                              totalMentions: ctxs.count, contexts: ctxs,
                              sentimentScore: nil, daily: nil)
        }
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

    private func freshURL(from baseURL: URL) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "_ts" }
        queryItems.append(URLQueryItem(name: "_ts", value: String(Int(Date().timeIntervalSince1970))))
        components.queryItems = queryItems
        return components.url
    }
}
