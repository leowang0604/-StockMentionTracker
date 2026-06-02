import Foundation

struct AliasCandidate: Codable, Identifiable {
    let wrongKeyword: String
    let correctCode: String
    let correctName: String
    let confidence: String
    let maxScore: Int
    let observations: Int
    let distinctVideos: Int
    let videoIDs: [String]
    let evidence: [AliasEvidence]
    let updatedAt: String

    var id: String { "\(wrongKeyword)|\(correctCode)" }

    enum CodingKeys: String, CodingKey {
        case confidence, evidence, observations
        case wrongKeyword = "wrong_keyword"
        case correctCode = "correct_code"
        case correctName = "correct_name"
        case maxScore = "max_score"
        case distinctVideos = "distinct_videos"
        case videoIDs = "video_ids"
        case updatedAt = "updated_at"
    }
}

struct AliasEvidence: Codable, Identifiable {
    let videoID: String
    let channel: String
    let date: String
    let title: String
    let source: String
    let score: Int
    let reasons: [String]
    let context: String

    var id: String { "\(videoID)|\(source)|\(context)" }

    enum CodingKeys: String, CodingKey {
        case channel, context, date, reasons, score, source, title
        case videoID = "video_id"
    }
}

struct RejectedAlias: Codable {
    let wrongKeyword: String
    let correctCode: String
    let correctName: String
    let rejectedAt: String

    enum CodingKeys: String, CodingKey {
        case wrongKeyword = "wrong_keyword"
        case correctCode = "correct_code"
        case correctName = "correct_name"
        case rejectedAt = "rejected_at"
    }
}
