import Foundation

// MARK: - Channel Source (from scanner/sources.json)

struct ChannelSource: Codable, Identifiable {
    let id: String
    let name: String
    let type: String       // "youtube"
    let identifier: String // YouTube Channel ID
    var active: Bool
    var extractionMode: String?  // "keyword" | "auto" | "gemini"; nil = use global

    var sourceType: SourceType {
        SourceType(rawValue: type) ?? .youtube
    }

    enum CodingKeys: String, CodingKey {
        case id, name, type, identifier, active
        case extractionMode = "extraction_mode"
    }
}

// MARK: - Source Type

enum SourceType: String, Codable, CaseIterable {
    case youtube = "youtube"
    case applePodcast = "applePodcast"
    case spotify = "spotify"

    var displayName: String {
        switch self {
        case .youtube: return "YouTube"
        case .applePodcast: return "Apple Podcast"
        case .spotify: return "Spotify"
        }
    }

    var icon: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .applePodcast: return "mic.fill"
        case .spotify: return "music.note"
        }
    }
}

// MARK: - Sources Config (scanner/sources.json)

struct SourcesConfig: Codable {
    var sources: [ChannelSource]
    var globalExtractionMode: String?  // "keyword" | "auto" | "gemini"

    enum CodingKeys: String, CodingKey {
        case sources
        case globalExtractionMode = "global_extraction_mode"
    }
}
