import Foundation

// MARK: - Mention Info (from latest.json)

struct MentionInfo: Codable, Identifiable {
    let stockCode: String
    let stockName: String
    let mentionedAt: String
    let context: String
    let analysisSource: String
    let sourceType: String
    let sourceName: String
    let episodeId: String
    let episodeTitle: String

    var id: String { stockCode + "_" + episodeId + "_" + mentionedAt }

    enum CodingKeys: String, CodingKey {
        case stockCode = "stock_code"
        case stockName = "stock_name"
        case mentionedAt = "mentioned_at"
        case context
        case analysisSource = "analysis_source"
        case sourceType = "source_type"
        case sourceName = "source_name"
        case episodeId = "episode_id"
        case episodeTitle = "episode_title"
    }

    var mentionedDate: Date {
        ISO8601DateFormatter().date(from: mentionedAt) ?? Date()
    }

    var dateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.locale = Locale(identifier: "zh_TW")
        return formatter.string(from: mentionedDate)
    }

    var analysisSourceIcon: String {
        switch analysisSource {
        case "transcript": return "🎙"
        case "titleAndDescription": return "📄"
        default: return "📊"
        }
    }

    var analysisSourceDisplay: String {
        switch analysisSource {
        case "transcript": return "字幕/逐字稿"
        case "titleAndDescription": return "標題+描述"
        default: return analysisSource
        }
    }
}

// MARK: - Stock Ranking Item (for UI)

struct StockRankingItem: Identifiable {
    let id: String         // stockCode
    let stockCode: String
    let stockName: String
    let totalMentions: Int
    let sourceCount: Int
    let lastMentionedAt: Date
    let analysisSources: Set<String>
    let mentions: [MentionInfo]

    var lastMentionedText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastMentionedAt, relativeTo: Date())
    }

    var analysisSourceIcons: String {
        var icons = ""
        if analysisSources.contains("transcript") { icons += "🎙" }
        if analysisSources.contains("titleAndDescription") { icons += "📄" }
        return icons
    }
}
