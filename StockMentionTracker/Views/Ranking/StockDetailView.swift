import SwiftUI

struct StockDetailView: View {
    let stock: StockEntry

    @Environment(DataService.self) private var dataService
    @Environment(AppState.self)    private var appState

    @State private var expandedIDs = Set<String>()
    @State private var contextSort = "newest"  // newest | oldest | count

    private var sortedContexts: [MentionContext] {
        switch contextSort {
        case "oldest":
            return stock.contexts.sorted { ($0.parsedDate ?? .distantPast) < ($1.parsedDate ?? .distantPast) }
        case "count":
            let perVideo = Dictionary(grouping: stock.contexts, by: \.video).mapValues(\.count)
            return stock.contexts.sorted {
                let c0 = perVideo[$0.video, default: 1], c1 = perVideo[$1.video, default: 1]
                if c0 != c1 { return c0 > c1 }
                return ($0.parsedDate ?? .distantPast) > ($1.parsedDate ?? .distantPast)
            }
        default: // newest
            return stock.contexts.sorted { ($0.parsedDate ?? .distantPast) > ($1.parsedDate ?? .distantPast) }
        }
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
            Section {
                if stock.contexts.isEmpty {
                    Text("無提及紀錄")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(sortedContexts) { ctx in
                        ContextRowView(
                            context: ctx,
                            highlightTerms: highlightTerms(for: ctx),
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
            } header: {
                HStack {
                    Text("提及紀錄（\(stock.contexts.count) 筆）")
                    Spacer()
                    Menu {
                        Button {
                            contextSort = "newest"
                        } label: {
                            Label("最新日期", systemImage: contextSort == "newest" ? "checkmark" : "")
                        }
                        Button {
                            contextSort = "oldest"
                        } label: {
                            Label("最舊日期", systemImage: contextSort == "oldest" ? "checkmark" : "")
                        }
                        Button {
                            contextSort = "count"
                        } label: {
                            Label("集數次數", systemImage: contextSort == "count" ? "checkmark" : "")
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(contextSort == "newest" ? "最新" : contextSort == "oldest" ? "最舊" : "次數")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(stock.name)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    private func highlightTerms(for context: MentionContext) -> [String] {
        mentionHighlightTerms(
            stockName: stock.name,
            code: stock.code,
            matchedKeyword: context.matchedKeyword
        )
    }
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

            // Extraction badges (AI 擷取 / 已修正)
            let showGeminiBadge   = context.extractionMode == "gemini"
            let showCorrectedBadge = context.whisperCorrected == true
            if showGeminiBadge || showCorrectedBadge {
                HStack(spacing: 6) {
                    if showGeminiBadge {
                        Text("AI 擷取")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                    if showCorrectedBadge {
                        Text("已修正")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.orange.opacity(0.12), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    if showCorrectedBadge, let kw = context.matchedKeyword, !kw.isEmpty {
                        Text("原文：\(kw)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Context text (expandable)
            if !context.text.isEmpty {
                Button(action: onToggle) {
                    HStack {
                        Text("提及內容")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    if let excerpt = mentionExcerpt(context.text, terms: highlightTerms) {
                        Text(highlightedMentionText("…\(excerpt)…", terms: highlightTerms))
                            .font(.caption)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text("此筆舊資料找不到對應的原文命中詞，等待重新掃描更新。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
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
