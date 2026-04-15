import SwiftUI

struct RadarView: View {
    @Environment(AppState.self)    private var appState
    @Environment(DataService.self) private var dataService

    private var allStocks: [StockEntry] {
        dataService.scanResult.stocksRanking
    }

    // 看多共識: sentiment_score > 0.7 AND mentions in selected window >= 2
    private var bullishConsensus: [StockEntry] {
        let cutoff = appState.cutoffDate
        return allStocks.filter { stock in
            guard let score = stock.sentimentScore else { return false }
            let recentCount = stock.contexts.filter {
                ($0.parsedDate ?? .distantPast) >= cutoff
            }.count
            return score > 0.7 && recentCount >= 2
        }.sorted { ($0.sentimentScore ?? 0) > ($1.sentimentScore ?? 0) }
    }

    // 看空共識: sentiment_score < 0.3 AND mentions in selected window >= 2
    private var bearishConsensus: [StockEntry] {
        let cutoff = appState.cutoffDate
        return allStocks.filter { stock in
            guard let score = stock.sentimentScore else { return false }
            let recentCount = stock.contexts.filter {
                ($0.parsedDate ?? .distantPast) >= cutoff
            }.count
            return score < 0.3 && recentCount >= 2
        }.sorted { ($0.sentimentScore ?? 1) < ($1.sentimentScore ?? 1) }
    }

    // 區間提及次數：使用 selectedDays 為窗口大小
    private func periodMentions(_ stock: StockEntry, periodsAgo: Int) -> Int {
        let days = Int(appState.selectedDays)
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days * (periodsAgo + 1), to: now) ?? now
        let end   = Calendar.current.date(byAdding: .day, value: -days * periodsAgo, to: now) ?? now
        let filtered = stock.contexts.filter {
            guard let d = $0.parsedDate else { return false }
            return d >= start && d < end
        }
        return Set(filtered.map { "\($0.channel ?? "")_\($0.video)" }).count
    }

    // 近期暴紅: this period > last period * 2 AND last period > 0 AND this period >= 2
    private var hotThisWeek: [StockEntry] {
        allStocks.filter { stock in
            let cur  = periodMentions(stock, periodsAgo: 0)
            let prev = periodMentions(stock, periodsAgo: 1)
            guard cur >= 2, prev > 0 else { return false }
            return Double(cur) / Double(prev) > 2.0
        }.sorted { periodMentions($0, periodsAgo: 0) > periodMentions($1, periodsAgo: 0) }
    }

    // 近期新上榜: this period >= 1 AND last period == 0
    private var newThisWeek: [StockEntry] {
        allStocks.filter { stock in
            let cur  = periodMentions(stock, periodsAgo: 0)
            let prev = periodMentions(stock, periodsAgo: 1)
            return cur >= 1 && prev == 0
        }.sorted { periodMentions($0, periodsAgo: 0) > periodMentions($1, periodsAgo: 0) }
    }

    // 近期降溫: this period < last period * 0.5 AND last period >= 2
    private var coolingThisWeek: [StockEntry] {
        allStocks.filter { stock in
            let cur  = periodMentions(stock, periodsAgo: 0)
            let prev = periodMentions(stock, periodsAgo: 1)
            guard prev >= 2 else { return false }
            return Double(cur) / Double(prev) < 0.5
        }.sorted { periodMentions($0, periodsAgo: 1) > periodMentions($1, periodsAgo: 1) }
    }

    var body: some View {
        @Bindable var appState = appState
        return NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("最近")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $appState.selectedDays, in: 1...90, step: 1)
                    Text("\(Int(appState.selectedDays)) 天")
                        .font(.caption.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                Divider()

                List {
                radarSection(
                    title: "看多共識",
                    icon: "arrow.up.circle.fill",
                    color: .green,
                    stocks: bullishConsensus,
                    emptyHint: "目前無看多股票（需情緒 > 70% 且近期提及 ≥ 2 次）",
                    subtitle: { stock in
                        let score = stock.sentimentScore.map { String(format: "%.0f%%", $0 * 100) } ?? ""
                        return "看多 \(score) · \(stock.episodeCount) 集提及"
                    }
                )
                radarSection(
                    title: "看空共識",
                    icon: "arrow.down.circle.fill",
                    color: .red,
                    stocks: bearishConsensus,
                    emptyHint: "目前無看空股票（需情緒 < 30% 且近期提及 ≥ 2 次）",
                    subtitle: { stock in
                        let score = stock.sentimentScore.map { String(format: "%.0f%%", (1 - $0) * 100) } ?? ""
                        return "看空 \(score) · \(stock.episodeCount) 集提及"
                    }
                )
                radarSection(
                    title: "近期暴紅",
                    icon: "flame.fill",
                    color: .orange,
                    stocks: hotThisWeek,
                    emptyHint: "近期無暴紅股票（需本期提及 ≥ 2 次且為上期 2 倍以上）",
                    subtitle: { stock in
                        let cur  = periodMentions(stock, periodsAgo: 0)
                        let prev = periodMentions(stock, periodsAgo: 1)
                        let ratio = prev > 0 ? String(format: "+%.0f%%", (Double(cur) / Double(prev) - 1) * 100) : ""
                        return "本期 \(cur) 集 \(ratio)"
                    }
                )
                radarSection(
                    title: "近期新上榜",
                    icon: "sparkle",
                    color: .purple,
                    stocks: newThisWeek,
                    emptyHint: "近期無新上榜股票（上期未被提及、本期首次出現）",
                    subtitle: { stock in
                        let cur = periodMentions(stock, periodsAgo: 0)
                        return "首次出現 · \(cur) 集"
                    }
                )
                radarSection(
                    title: "近期降溫",
                    icon: "snowflake",
                    color: .blue,
                    stocks: coolingThisWeek,
                    emptyHint: "近期無降溫股票（需上期提及 ≥ 2 次且本期不到上期一半）",
                    subtitle: { stock in
                        let cur  = periodMentions(stock, periodsAgo: 0)
                        let prev = periodMentions(stock, periodsAgo: 1)
                        let ratio = prev > 0 ? String(format: "%.0f%%", Double(cur) / Double(prev) * 100) : "0%"
                        return "本期 \(cur) 集（上期 \(prev) 集，剩 \(ratio)）"
                    }
                )
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("投資雷達")
        }
    }

    @ViewBuilder
    private func radarSection(
        title: String,
        icon: String,
        color: Color,
        stocks: [StockEntry],
        emptyHint: String,
        subtitle: @escaping (StockEntry) -> String
    ) -> some View {
        Section {
            if stocks.isEmpty {
                Text(emptyHint)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding(.vertical, 2)
            } else {
                ForEach(stocks.prefix(10)) { stock in
                    NavigationLink {
                        let cutoff = appState.cutoffDate
                        let ctxs = stock.contexts.filter { ($0.parsedDate ?? .distantPast) >= cutoff }
                        let filtered = StockEntry(
                            code: stock.code, name: stock.name,
                            market: stock.market, sector: stock.sector,
                            totalMentions: ctxs.count, contexts: ctxs,
                            sentimentScore: stock.sentimentScore, daily: stock.daily
                        )
                        StockDetailView(stock: filtered)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: icon)
                                .foregroundStyle(color)
                                .font(.title3)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(stock.name).font(.headline)
                                    if !stock.marketLabel.isEmpty {
                                        Text(stock.marketLabel)
                                            .font(.caption2)
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(.quaternary, in: Capsule())
                                    }
                                }
                                Text(subtitle(stock))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        } header: {
            Label(title, systemImage: icon)
                .foregroundStyle(color)
        }
    }
}
