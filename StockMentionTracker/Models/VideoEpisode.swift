import Foundation

// MARK: - Scanned video / podcast episode (from videos_scanned)

struct VideoScanned: Codable, Identifiable {
    let videoId: String?
    let title: String
    let channel: String
    let date: String
    let stocksFound: [String]
    let analysisSource: String?
    let thumbnailUrl: String?

    var id: String { videoId ?? (title + date) }

    enum CodingKeys: String, CodingKey {
        case videoId       = "video_id"
        case title, channel, date
        case stocksFound   = "stocks_found"
        case analysisSource = "analysis_source"
        case thumbnailUrl  = "thumbnail_url"
    }

    var parsedDate: Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: date)
    }

    var dateText: String {
        guard let d = parsedDate else { return date }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.locale    = Locale(identifier: "zh_TW")
        return f.string(from: d)
    }

    var externalURL: URL? {
        guard let vid = videoId else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(vid)")
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
        default:                    return analysisSource ?? "未知"
        }
    }
}
