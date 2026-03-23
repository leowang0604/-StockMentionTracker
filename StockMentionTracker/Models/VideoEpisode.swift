import Foundation

// MARK: - Episode Info (from latest.json)

struct EpisodeInfo: Codable, Identifiable {
    let id: String
    let title: String
    let publishedAt: String
    let sourceType: String
    let sourceName: String
    let thumbnailURL: String?
    let analysisSource: String
    let mentionedStocks: [String]  // stock codes

    enum CodingKeys: String, CodingKey {
        case id, title
        case publishedAt = "published_at"
        case sourceType = "source_type"
        case sourceName = "source_name"
        case thumbnailURL = "thumbnail_url"
        case analysisSource = "analysis_source"
        case mentionedStocks = "mentioned_stocks"
    }

    var publishedDate: Date {
        ISO8601DateFormatter().date(from: publishedAt) ?? Date()
    }

    var publishedDateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "zh_TW")
        return formatter.string(from: publishedDate)
    }

    var sourceTypeEnum: SourceType {
        SourceType(rawValue: sourceType) ?? .youtube
    }

    var externalURL: URL? {
        switch sourceTypeEnum {
        case .youtube:
            return URL(string: "https://www.youtube.com/watch?v=\(id)")
        case .applePodcast:
            return URL(string: "https://podcasts.apple.com/podcast/id\(id)")
        case .spotify:
            return URL(string: "https://open.spotify.com/episode/\(id)")
        }
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
