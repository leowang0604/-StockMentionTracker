import Foundation

// MARK: - Scan Result (latest.json top-level model)

struct ScanResult: Codable {
    let generatedAt: String
    let sources: [ChannelSource]
    let episodes: [EpisodeInfo]
    let mentions: [MentionInfo]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case sources, episodes, mentions
    }

    var generatedDate: Date {
        ISO8601DateFormatter().date(from: generatedAt) ?? Date()
    }

    static let empty = ScanResult(
        generatedAt: "",
        sources: [],
        episodes: [],
        mentions: []
    )
}
