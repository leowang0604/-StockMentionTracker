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
    let phoneticCandidates: [PhoneticAliasCandidate]?
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
        case phoneticCandidates = "phonetic_candidates"
        case updatedAt = "updated_at"
    }
}

struct PhoneticAliasCandidate: Codable, Identifiable {
    let code: String
    let name: String
    let score: Double
    let phoneticSimilarity: Double
    let textSimilarity: Double

    var id: String { code }

    enum CodingKeys: String, CodingKey {
        case code, name, score
        case phoneticSimilarity = "phonetic_similarity"
        case textSimilarity = "text_similarity"
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
    let overrideKind: String?
    let overrideReason: String?
    let originalCode: String?
    let originalName: String?
    let phoneticTopScore: Double?
    let phoneticLead: Double?

    var id: String { "\(videoID)|\(source)|\(context)" }

    enum CodingKeys: String, CodingKey {
        case channel, context, date, reasons, score, source, title
        case videoID = "video_id"
        case overrideKind = "override_kind"
        case overrideReason = "override_reason"
        case originalCode = "original_code"
        case originalName = "original_name"
        case phoneticTopScore = "phonetic_top_score"
        case phoneticLead = "phonetic_lead"
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
