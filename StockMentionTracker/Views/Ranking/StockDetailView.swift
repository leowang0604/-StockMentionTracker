import SwiftUI

struct StockDetailView: View {
    let stock: StockEntry

    @Environment(DataService.self) private var dataService
    @Environment(AppState.self)    private var appState

    @State private var expandedIDs = Set<String>()

    /// All distinct keywords matched across every context for this stock.
    /// Uses ALL unfiltered contexts from dataService so date-window filtering
    /// doesn't strip out the keywords we need for highlighting.
    private var allHighlightTerms: [String] {
        let fullContexts = dataService.scanResult.stocksRanking
            .first { $0.code == stock.code }?.contexts ?? stock.contexts
        let keywords = fullContexts.compactMap(\.matchedKeyword).filter { !$0.isEmpty }
        let base = shortNameTerms(stock.name, stock.code, nil)
        return Array(Set(base + keywords))
    }

    private var sectorPeers: [StockEntry] {
        guard let sector = stock.sector, sector != "其他" else { return [] }
        @Bindable var appState = appState
        let cutoff = appState.cutoffDate
        return dataService.scanResult.stocksRanking
            .filter { $0.sector == sector && $0.code != stock.code && $0.market == stock.market }
            .compactMap { s -> StockEntry? in
                let ctxs = s.contexts.filter { ($0.parsedDate ?? .distantPast) >= cutoff }
                guard !ctxs.isEmpty else { return nil }
                return StockEntry(code: s.code, name: s.name,
                                  market: s.market, sector: s.sector,
                                  totalMentions: ctxs.count, contexts: ctxs,
                                  sentimentScore: nil, daily: nil)
            }
            .sorted { $0.totalMentions > $1.totalMentions }
    }

    var body: some View {
        List {
            // ── Header ────────────────────────────────────────────────────
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if !stock.marketLabel.isEmpty {
                                Text(stock.marketLabel)
                            }
                            Text(stock.name).font(.title2.bold())
                            Text(stock.code)
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let sector = stock.sector {
                            Text(sector)
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.blue.opacity(0.12), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                        Text("提及集數：\(stock.episodeCount) 集（共 \(stock.totalMentions) 次）")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("涵蓋來源：\(stock.channelCount) 個")
                            .font(.caption).foregroundStyle(.tertiary)
                        SentimentCountRow(contexts: stock.contexts)
                        if let score = stock.sentimentScore {
                            SentimentBar(score: score, label: stock.sentimentLabel)
                        }
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(stock.analysisSourceSymbols, id: \.self) {
                            Image(systemName: $0).font(.title2)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // ── Sector peers ──────────────────────────────────────────────
            if !sectorPeers.isEmpty {
                Section("同族群個股") {
                    // Current stock (highlighted)
                    HStack {
                        Text(stock.name).font(.subheadline.bold())
                        Text(stock.code).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(stock.totalMentions) 次")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(Color.accentColor.opacity(0.1))

                    ForEach(Array(sectorPeers.enumerated()), id: \.element.id) { _, peer in
                        NavigationLink {
                            StockDetailView(stock: peer)
                        } label: {
                            HStack {
                                Text(peer.name).font(.subheadline)
                                Text(peer.code).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(peer.totalMentions) 次")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            // ── Mention list ──────────────────────────────────────────────
            Section("提及紀錄（\(stock.contexts.count) 筆）") {
                if stock.contexts.isEmpty {
                    Text("無提及紀錄")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(stock.contexts) { ctx in
                        ContextRowView(
                            context: ctx,
                            highlightTerms: allHighlightTerms,
                            isExpanded: expandedIDs.contains(ctx.id),
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedIDs.contains(ctx.id) {
                                        expandedIDs.remove(ctx.id)
                                    } else {
                                        expandedIDs.insert(ctx.id)
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle(stock.name)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

/// Builds highlight terms from stock name, code, and matchedKeyword.
/// Also extracts the short name (before ", " or " Inc"/" Ltd" etc.) so that
/// "Cloudflare, Inc." → also searches "Cloudflare".
private func shortNameTerms(_ name: String, _ code: String, _ keyword: String?) -> [String] {
    var terms: [String] = []
    terms.append(name)
    // Short name: strip English legal suffixes
    // e.g. "Cloudflare, Inc." → "Cloudflare", "Adobe Inc." → "Adobe"
    let commaStripped = name
        .components(separatedBy: ",").first?
        .trimmingCharacters(in: .whitespaces) ?? name
    if commaStripped != name { terms.append(commaStripped) }
    let englishSuffixes = [" Inc.", " Inc", " Corp.", " Corp", " Corporation",
                           " LLC", " Ltd.", " Ltd", " Co.", " Holdings", " Group"]
    let baseForSuffix = commaStripped
    for suffix in englishSuffixes {
        if baseForSuffix.hasSuffix(suffix) {
            let s = String(baseForSuffix.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            if s != name && s.count >= 2 { terms.append(s) }
            break
        }
    }
    // Short name: strip Chinese company suffixes repeatedly
    // e.g. "南俊國際股份有限公司" → "南俊國際" → "南俊"
    let chineseSuffixes = ["股份有限公司", "有限公司", "投資控股", "投控", "控股",
                           "光電工業", "光電", "電子工業", "電子", "科技工業", "科技",
                           "電腦", "工業", "企業", "實業", "國際"]
    var current = name
    outer: while true {
        for suffix in chineseSuffixes {
            if current.hasSuffix(suffix) {
                current = String(current.dropLast(suffix.count))
                if current.count >= 2 { terms.append(current) }
                continue outer
            }
        }
        break
    }
    terms.append(code)
    if let kw = keyword, !kw.isEmpty { terms.append(kw) }
    return terms.filter { !$0.isEmpty }
}

// MARK: - Context Row

struct ContextRowView: View {
    let context: MentionContext
    var highlightTerms: [String] = []
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Channel + date + analysis source badge
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 2) {
                    if let channelName = context.channel {
                        NavigationLink {
                            ChannelDetailView(channelName: channelName)
                        } label: {
                            Text(channelName)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("未知來源")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    }
                    Text(context.dateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !context.sentimentLabel.isEmpty {
                    Text(context.sentimentLabel)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(sentimentColor(context).opacity(0.15), in: Capsule())
                        .foregroundStyle(sentimentColor(context))
                }

                HStack(spacing: 3) {
                    Image(systemName: context.analysisSourceSymbol)
                    Text(context.analysisSourceDisplay)
                        .font(.caption2)
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(analysisColor.opacity(0.15), in: Capsule())
                .foregroundStyle(analysisColor)
            }

            // Video title (tappable if URL available)
            if let urlString = context.videoURL, let url = URL(string: urlString) {
                Link(destination: url) {
                    Text(context.video)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .lineLimit(isExpanded ? nil : 1)
                }
            } else {
                Text(context.video)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : 1)
            }

            // Context text (expandable)
            if !context.text.isEmpty {
                Button(action: onToggle) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("提及內容")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if isExpanded {
                            Text(highlighted("…\(context.text)…"))
                                .font(.caption)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func highlighted(_ raw: String) -> AttributedString {
        var attributed = AttributedString(raw)
        for term in highlightTerms where !term.isEmpty {
            var searchFrom = raw.startIndex
            while searchFrom < raw.endIndex,
                  let found = raw.range(of: term, options: .caseInsensitive, range: searchFrom..<raw.endIndex) {
                let offset = raw.distance(from: raw.startIndex, to: found.lowerBound)
                let length = raw.distance(from: found.lowerBound, to: found.upperBound)
                let lo = attributed.characters.index(attributed.startIndex, offsetBy: offset)
                let hi = attributed.characters.index(lo, offsetBy: length)
                attributed[lo..<hi].foregroundColor = .orange
                attributed[lo..<hi].inlinePresentationIntent = .stronglyEmphasized
                searchFrom = found.upperBound
            }
        }
        return attributed
    }

    private var analysisColor: Color {
        switch context.analysisSource {
        case "whisper":  return .blue
        case "captions": return .teal
        default:         return .gray
        }
    }

    private func sentimentColor(_ ctx: MentionContext) -> Color {
        switch ctx.sentiment {
        case "bullish": return .green
        case "bearish": return .red
        default:        return .secondary
        }
    }
}

// MARK: - Sentiment Count Row

struct SentimentCountRow: View {
    let contexts: [MentionContext]

    private var bullish: Int { contexts.filter { $0.sentiment == "bullish" }.count }
    private var bearish: Int { contexts.filter { $0.sentiment == "bearish" }.count }
    private var neutral: Int { contexts.filter { $0.sentiment == "neutral" }.count }
    private var hasData: Bool { bullish + bearish + neutral > 0 }

    var body: some View {
        if hasData {
            HStack(spacing: 12) {
                sentimentChip("看多", count: bullish, color: .green)
                sentimentChip("看空", count: bearish, color: .red)
                sentimentChip("中性", count: neutral, color: .secondary)
            }
            .font(.caption)
        }
    }

    private func sentimentChip(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(color)
            Text("\(count)").foregroundStyle(.primary).monospacedDigit()
        }
    }
}

// MARK: - Sentiment Bar

struct SentimentBar: View {
    let score: Double
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("市場情緒")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(label)
                    .font(.caption.bold())
                    .foregroundStyle(barColor)
                Text(String(format: "%.0f%%", displayPercentage))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(barColor)
                        .frame(width: geo.size.width * score)
                }
            }
            .frame(height: 6)
        }
        .padding(.top, 4)
    }

    private var barColor: Color {
        if score > 0.6 { return .green }
        if score < 0.4 { return .red }
        return .secondary
    }

    /// 顯示「朝該方向的強度」：看多 → score%；看空 → (1-score)%；中性 → 50%
    private var displayPercentage: Double {
        if score > 0.6 { return score * 100 }
        if score < 0.4 { return (1 - score) * 100 }
        return 50
    }
}
