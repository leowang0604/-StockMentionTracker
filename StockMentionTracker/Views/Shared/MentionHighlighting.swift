import SwiftUI

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

    terms.append(code)
    if let matchedKeyword, !matchedKeyword.isEmpty {
        terms.append(matchedKeyword)
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

private func normalizedHighlightSource(_ text: String) -> String {
    text.replacingOccurrences(of: "臺", with: "台")
}

private func containsOnlyCJK(_ text: String) -> Bool {
    !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }
}

private func shouldFuzzyMatch(_ term: String) -> Bool {
    let normalized = normalizedHighlightSource(term)
    let count = normalized.count
    return containsOnlyCJK(normalized) && (3...4).contains(count)
}

private func oneCharOff(_ lhs: String, _ rhs: String) -> Bool {
    let left = Array(normalizedHighlightSource(lhs))
    let right = Array(normalizedHighlightSource(rhs))
    guard left.count == right.count, !left.isEmpty else { return false }
    var diffCount = 0
    for (l, r) in zip(left, right) where l != r {
        diffCount += 1
        if diffCount > 1 { return false }
    }
    return diffCount == 1
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

        guard shouldFuzzyMatch(term) else { continue }

        let termChars = Array(term)
        let rawChars = Array(raw)
        let windowSize = termChars.count
        guard rawChars.count >= windowSize else { continue }

        for start in 0...(rawChars.count - windowSize) {
            let candidate = String(rawChars[start..<(start + windowSize)])
            if candidate.caseInsensitiveCompare(term) == .orderedSame {
                continue
            }
            guard oneCharOff(candidate, term) else { continue }
            highlightRange(&attributed, offset: start, length: windowSize)
        }
    }
    return attributed
}
