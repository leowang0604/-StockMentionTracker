import SwiftUI

private let ambiguousStandaloneTickerHighlightCodes: Set<String> = ["AI"]

private func isAmbiguousStandaloneTicker(_ term: String, code: String) -> Bool {
    ambiguousStandaloneTickerHighlightCodes.contains(code.uppercased())
        && term.caseInsensitiveCompare(code) == .orderedSame
}

/// Builds highlight terms from stock name, code, and matchedKeyword.
/// Also extracts shorter legal/company-name variants for display matching.
func mentionHighlightTerms(stockName name: String, code: String, matchedKeyword: String? = nil) -> [String] {
    var terms: [String] = []
    terms.append(name)

    let commaStripped = name
        .components(separatedBy: ",").first?
        .trimmingCharacters(in: .whitespaces) ?? name
    if commaStripped != name {
        terms.append(commaStripped)
    }

    let englishSuffixes = [" Inc.", " Inc", " Corp.", " Corp", " Corporation",
                           " LLC", " Ltd.", " Ltd", " Co.", " Holdings", " Group"]
    for suffix in englishSuffixes where commaStripped.hasSuffix(suffix) {
        let shortName = String(commaStripped.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        if shortName != name, shortName.count >= 2 {
            terms.append(shortName)
        }
        break
    }

    let chineseSuffixes = ["股份有限公司", "有限公司", "投資控股", "投控", "控股",
                           "光電工業", "光電", "電子工業", "電子", "科技工業", "科技",
                           "電腦", "工業", "企業", "實業", "國際"]
    var current = name
    outer: while true {
        for suffix in chineseSuffixes where current.hasSuffix(suffix) {
            current = String(current.dropLast(suffix.count))
            if current.count >= 2 {
                terms.append(current)
            }
            continue outer
        }
        break
    }

    if !isAmbiguousStandaloneTicker(code, code: code) {
        terms.append(code)
    }
    if let matchedKeyword, !matchedKeyword.isEmpty {
        if !isAmbiguousStandaloneTicker(matchedKeyword, code: code) {
            terms.append(matchedKeyword)
        }
    }

    let withTaiwanVariants = terms.flatMap { term -> [String] in
        var variants = [term]
        if term.contains("台") {
            variants.append(term.replacingOccurrences(of: "台", with: "臺"))
        }
        if term.contains("臺") {
            variants.append(term.replacingOccurrences(of: "臺", with: "台"))
        }
        return variants
    }

    return Array(Set(withTaiwanVariants))
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .sorted { $0.count > $1.count }
}

private func highlightRange(
    _ attributed: inout AttributedString,
    offset: Int,
    length: Int
) {
    let lo = attributed.characters.index(attributed.startIndex, offsetBy: offset)
    let hi = attributed.characters.index(lo, offsetBy: length)
    attributed[lo..<hi].foregroundColor = .black
    attributed[lo..<hi].backgroundColor = Color.yellow.opacity(0.9)
    attributed[lo..<hi].inlinePresentationIntent = .stronglyEmphasized
}

/// Keeps legacy oversized scanner contexts readable until their source episode
/// is replayed. New scanner output is already bounded to the same 303 characters.
func mentionExcerpt(_ raw: String, terms: [String], maxCharacters: Int = 303) -> String? {
    let ranges = terms.compactMap { term -> Range<String.Index>? in
        guard !term.isEmpty else { return nil }
        return raw.range(of: term, options: .caseInsensitive)
    }
    guard let firstMatch = ranges.min(by: { $0.lowerBound < $1.lowerBound }) else {
        return nil
    }

    guard raw.count > maxCharacters else { return raw }
    let matchOffset = raw.distance(from: raw.startIndex, to: firstMatch.lowerBound)
    let startOffset = max(0, matchOffset - 100)
    let start = raw.index(raw.startIndex, offsetBy: startOffset)
    return String(raw[start...].prefix(maxCharacters))
}

func highlightedMentionText(_ raw: String, terms: [String]) -> AttributedString {
    var attributed = AttributedString(raw)
    for term in terms where !term.isEmpty {
        var searchFrom = raw.startIndex
        while searchFrom < raw.endIndex,
              let found = raw.range(of: term, options: .caseInsensitive, range: searchFrom..<raw.endIndex) {
            let offset = raw.distance(from: raw.startIndex, to: found.lowerBound)
            let length = raw.distance(from: found.lowerBound, to: found.upperBound)
            highlightRange(&attributed, offset: offset, length: length)
            searchFrom = found.upperBound
        }

    }
    return attributed
}
