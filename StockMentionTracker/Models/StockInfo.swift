import Foundation

// MARK: - Weekly Summary

struct WeeklySummary: Codable {
    let text: String
    let hotStocks: [String]
    let keyThemes: [String]
    let generatedAt: String

    enum CodingKeys: String, CodingKey {
        case text
        case hotStocks   = "hot_stocks"
        case keyThemes   = "key_themes"
        case generatedAt = "generated_at"
    }
}

// MARK: - Top-level scan result

struct ScanResult: Codable {
    let updatedAt: String
    let stocksRanking: [StockEntry]
    let sectorsRanking: [SectorEntry]?
    let videosScanned: [VideoScanned]
    let weeklySummary: WeeklySummary?

    static let empty = ScanResult(updatedAt: "", stocksRanking: [], sectorsRanking: nil, videosScanned: [], weeklySummary: nil)

    enum CodingKeys: String, CodingKey {
        case updatedAt      = "updated_at"
        case stocksRanking  = "stocks_ranking"
        case sectorsRanking = "sectors_ranking"
        case videosScanned  = "videos_scanned"
        case weeklySummary  = "weekly_summary"
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

// MARK: - Sector entry (one row in sectors_ranking)

struct SectorEntry: Codable, Identifiable {
    let sector: String
    let market: String?
    let totalMentions: Int
    let stockCodes: [String]

    var id: String { "\(market ?? "")_\(sector)" }

    enum CodingKeys: String, CodingKey {
        case sector, market
        case totalMentions = "total_mentions"
        case stockCodes    = "stock_codes"
    }

    var marketLabel: String {
        switch market {
        case "US": return "US"
        case "TW": return "TW"
        default:   return ""
        }
    }
}

// MARK: - Daily stats for a stock (one entry per day)

struct DailyStats: Codable {
    let mentions: Int
    let bullish:  Int
    let bearish:  Int
    let neutral:  Int
    let sentimentScore: Double

    enum CodingKeys: String, CodingKey {
        case mentions, bullish, bearish, neutral
        case sentimentScore = "sentiment_score"
    }
}

// MARK: - Stock entry (one row in stocks_ranking)

struct StockEntry: Codable, Identifiable {
    let code: String
    let name: String
    let market: String?   // "TW" or "US"
    let sector: String?   // e.g. "AI晶片"
    let totalMentions: Int
    let contexts: [MentionContext]
    let sentimentScore: Double?
    let daily: [String: DailyStats]?

    var id: String { code }

    enum CodingKeys: String, CodingKey {
        case code, name, market, sector
        case totalMentions = "total_mentions"
        case contexts
        case sentimentScore = "sentiment_score"
        case daily
    }

    var marketLabel: String {
        switch market {
        case "US": return "US"
        case "TW": return "TW"
        default:   return ""
        }
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

    /// Number of distinct episodes (channel + video title) mentioning this stock
    var episodeCount: Int {
        Set(contexts.map { "\($0.channel ?? "")_\($0.video)" }).count
    }

    var analysisSourceSymbols: [String] {
        let sources = Set(contexts.compactMap(\.analysisSource))
        var result: [String] = []
        if sources.contains("whisper")             { result.append("waveform") }
        if sources.contains("captions")            { result.append("captions.bubble") }
        if sources.contains("titleAndDescription") { result.append("doc.text") }
        return result
    }

    var sentimentLabel: String {
        guard let score = sentimentScore else { return "" }
        if score > 0.6 { return "看多" }
        if score < 0.4 { return "看空" }
        return "中性"
    }

    var sentimentColor: String {  // return color name as string for use in view
        guard let score = sentimentScore else { return "gray" }
        if score > 0.6 { return "green" }
        if score < 0.4 { return "red" }
        return "gray"
    }
}

// MARK: - Individual mention with context

struct MentionContext: Codable, Identifiable {
    let video: String
    let channel: String?
    let date: String
    let text: String
    let matchedKeyword: String?
    let analysisSource: String?
    let sentiment: String?
    let videoURL: String?
    let extractionMode: String?   // "keyword" | "gemini"
    let whisperCorrected: Bool?

    var id: String { "\(date)_\(video.prefix(20))_\(text.prefix(10))" }

    enum CodingKeys: String, CodingKey {
        case video, channel, date, text
        case matchedKeyword   = "matched_keyword"
        case analysisSource   = "analysis_source"
        case sentiment
        case videoURL         = "video_url"
        case extractionMode   = "extraction_mode"
        case whisperCorrected = "whisper_corrected"
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

    var analysisSourceSymbol: String {
        switch analysisSource {
        case "whisper":             return "waveform"
        case "captions":            return "captions.bubble"
        case "titleAndDescription": return "doc.text"
        default:                    return "chart.bar"
        }
    }

    var analysisSourceDisplay: String {
        switch analysisSource {
        case "whisper":             return "Whisper 逐字稿"
        case "captions":            return "字幕"
        case "titleAndDescription": return "標題+描述"
        default:                    return analysisSource ?? ""
        }
    }

    var sentimentIcon: String {
        switch sentiment {
        case "bullish": return "arrow.up.circle.fill"
        case "bearish": return "arrow.down.circle.fill"
        default:        return "minus.circle"
        }
    }

    var sentimentLabel: String {
        switch sentiment {
        case "bullish": return "看多"
        case "bearish": return "看空"
        case "neutral": return "中性"
        default:        return ""
        }
    }
}
