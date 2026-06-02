import Foundation

// MARK: - GitHub Service (for managing scanner/sources.json)

actor GitHubService {
    static let shared = GitHubService()
    private init() {}

    private struct FileContent: Codable {
        let content: String
        let sha: String
    }

    struct JSONFile<Value: Codable> {
        let value: Value
        let sha: String?
    }

    /// Read sources.json from GitHub repo
    func fetchSources(repo: String, pat: String) async throws -> (config: SourcesConfig, sha: String) {
        let url = try apiURL(repo: repo, path: "scanner/sources.json")
        var request = URLRequest(url: url)
        request.setValue("token \(pat)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw GitHubError.notFound
        }

        let fileContent = try JSONDecoder().decode(FileContent.self, from: data)
        let cleaned = fileContent.content.replacingOccurrences(of: "\n", with: "")
        guard let contentData = Data(base64Encoded: cleaned) else {
            throw GitHubError.decodeFailed
        }
        let config = try JSONDecoder().decode(SourcesConfig.self, from: contentData)
        return (config, fileContent.sha)
    }

    /// Write sources.json to GitHub repo
    func saveSources(config: SourcesConfig, repo: String, pat: String, sha: String) async throws {
        let url = try apiURL(repo: repo, path: "scanner/sources.json")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("token \(pat)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(config)
        let base64Content = jsonData.base64EncodedString()

        let body: [String: Any] = [
            "message": "Update sources via iOS app",
            "content": base64Content,
            "sha": sha
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...201).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GitHubError.saveFailedWithCode(code)
        }
    }

    /// Read a JSON file from the configured GitHub repo.
    func fetchJSON<Value: Codable>(
        _ type: Value.Type,
        repo: String,
        pat: String,
        path: String,
        defaultValue: Value? = nil
    ) async throws -> JSONFile<Value> {
        let url = try apiURL(repo: repo, path: path)
        var request = URLRequest(url: url)
        request.setValue("token \(pat)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        if statusCode == 404, let defaultValue {
            return JSONFile(value: defaultValue, sha: nil)
        }
        guard statusCode == 200 else {
            throw GitHubError.notFound
        }

        let fileContent = try JSONDecoder().decode(FileContent.self, from: data)
        let cleaned = fileContent.content.replacingOccurrences(of: "\n", with: "")
        guard let contentData = Data(base64Encoded: cleaned) else {
            throw GitHubError.decodeFailed
        }
        return JSONFile(
            value: try JSONDecoder().decode(Value.self, from: contentData),
            sha: fileContent.sha
        )
    }

    /// Create or update a JSON file in the configured GitHub repo.
    func saveJSON<Value: Codable>(
        _ value: Value,
        repo: String,
        pat: String,
        path: String,
        sha: String?,
        message: String
    ) async throws {
        let url = try apiURL(repo: repo, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("token \(pat)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var body: [String: Any] = [
            "message": message,
            "content": try encoder.encode(value).base64EncodedString()
        ]
        if let sha {
            body["sha"] = sha
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...201).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GitHubError.saveFailedWithCode(code)
        }
    }

    private func apiURL(repo: String, path: String) throws -> URL {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/contents/\(path)") else {
            throw GitHubError.invalidURL
        }
        return url
    }
}

enum GitHubError: LocalizedError {
    case notFound
    case saveFailed
    case saveFailedWithCode(Int)
    case invalidURL
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .notFound: return "找不到 sources.json（請確認 repo 路徑與 PAT）"
        case .saveFailed: return "儲存頻道列表失敗"
        case .saveFailedWithCode(let code): return "儲存失敗（HTTP \(code)）"
        case .invalidURL: return "無效的 GitHub repo 格式（應為 username/repo）"
        case .decodeFailed: return "解析 GitHub 回應失敗"
        }
    }
}
