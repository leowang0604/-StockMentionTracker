import Foundation

// MARK: - Top-level scan result

struct ScanResult: Codable {
    let updatedAt: String
    let stocksRanking: [StockEntry]
    let videosScanned: [VideoScanned]

    static let empty = ScanResult(updatedAt: "", stocksRanking: [], videosScanned: [])

    enum CodingKeys: String, CodingKey {
        case updatedAt     = "updated_at"
        case stocksRanking = "stocks_ranking"
        case videosScanned = "videos_scanned"
    }

    var updatedDate: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime,
                           .withDashSeparatorInDate, .withColonSeparatorInTime]
        return f.date(from: updatedAt)
    }

    var updatedDateText: String {
        guard let d = updatedDate else { return updatedAt }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale    = Locale(identifier: "zh_TW")
        return f.string(from: d)
    }
}

// MARK: - Stock entry (one row in stocks_ranking)

struct StockEntry: Codable, Identifiable {
    let code: String
    let name: String
    let totalMentions: Int
    let contexts: [MentionContext]

    var id: String { code }

    enum CodingKeys: String, CodingKey {
        case code, name
        case totalMentions = "total_mentions"
        case contexts
    }

    var lastDate: Date? {
        contexts.compactMap(\.parsedDate).max()
    }

    var lastDateText: String {
        guard let d = lastDate else { return "" }
        let f = DateFormatter()
        f.dateStyle = .short
        f.locale    = Locale(identifier: "zh_TW")
        return f.string(from: d)
    }

    var channelCount: Int {
        Set(contexts.compactMap(\.channel)).count
    }

    var analysisSourceIcons: String {
        let sources = Set(contexts.map(\.analysisSource))
        var s = ""
        if sources.contains("whisper")            { s += "🎙" }
        if sources.contains("captions")           { s += "📝" }
        if sources.contains("titleAndDescription") { s += "📄" }
        return s
    }
}

// MARK: - Individual mention with context

struct MentionContext: Codable, Identifiable {
    let video: String
    let channel: String?
    let date: String
    let text: String
    let analysisSource: String

    var id: String { "\(date)_\(video.prefix(20))_\(text.prefix(10))" }

    enum CodingKeys: String, CodingKey {
        case video, channel, date, text
        case analysisSource = "analysis_source"
    }

    var parsedDate: Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: date)
    }

    var dateText: String {
        guard let d = parsedDate else { return date }
        let f = DateFormatter()
        f.dateStyle = .short
        f.locale    = Locale(identifier: "zh_TW")
        return f.string(from: d)
    }

    var analysisSourceIcon: String {
        switch analysisSource {
        case "whisper":            return "🎙"
        case "captions":           return "📝"
        case "titleAndDescription": return "📄"
        default:                   return "📊"
        }
    }

    var analysisSourceDisplay: String {
        switch analysisSource {
        case "whisper":            return "Whisper 逐字稿"
        case "captions":           return "字幕"
        case "titleAndDescription": return "標題+描述"
        default:                   return analysisSource
        }
    }
}
