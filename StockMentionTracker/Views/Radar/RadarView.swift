import SwiftUI

struct RadarView: View {
    @Environment(AppState.self)    private var appState
    @Environment(DataService.self) private var dataService

    private var allStocks: [StockEntry] {
        dataService.scanResult.stocksRanking
    }

    // 看多共識: sentiment_score > 0.7 AND last 7 days mentions >= 5
    private var bullishConsensus: [StockEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return allStocks.filter { stock in
            guard let score = stock.sentimentScore else { return false }
            let recentCount = stock.contexts.filter {
                ($0.parsedDate ?? .distantPast) >= cutoff
            }.count
            return score > 0.7 && recentCount >= 5
        }.sorted { ($0.sentimentScore ?? 0) > ($1.sentimentScore ?? 0) }
    }

    // 看空共識: sentiment_score < 0.3 AND last 7 days mentions >= 5
    private var bearishConsensus: [StockEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return allStocks.filter { stock in
            guard let score = stock.sentimentScore else { return false }
            let recentCount = stock.contexts.filter {
                ($0.parsedDate ?? .distantPast) >= cutoff
            }.count
            return score < 0.3 && recentCount >= 5
        }.sorted { ($0.sentimentScore ?? 1) < ($1.sentimentScore ?? 1) }
    }

    // 本週提及次數
    private func weeklyMentions(_ stock: StockEntry, weeksAgo: Int) -> Int {
        let now = Date()
        let weekStart = Calendar.current.date(byAdding: .day, value: -7 * (weeksAgo + 1), to: now) ?? now
        let weekEnd   = Calendar.current.date(byAdding: .day, value: -7 * weeksAgo, to: now) ?? now
        return stock.contexts.filter {
            guard let d = $0.parsedDate else { return false }
            return d >= weekStart && d < weekEnd
        }.count
    }

    // 本週暴紅: this week > last week * 2 AND this week >= 3
    private var hotThisWeek: [StockEntry] {
        allStocks.filter { stock in
            let thisWeek = weeklyMentions(stock, weeksAgo: 0)
            let lastWeek = weeklyMentions(stock, weeksAgo: 1)
            guard thisWeek >= 3 else { return false }
            if lastWeek == 0 { return thisWeek >= 3 }
            return Double(thisWeek) / Double(lastWeek) > 2.0
        }.sorted { weeklyMentions($0, weeksAgo: 0) > weeklyMentions($1, weeksAgo: 0) }
    }

    // 本週降溫: this week < last week * 0.5 AND last week >= 3
    private var coolingThisWeek: [StockEntry] {
        allStocks.filter { stock in
            let thisWeek = weeklyMentions(stock, weeksAgo: 0)
            let lastWeek = weeklyMentions(stock, weeksAgo: 1)
            guard lastWeek >= 3 else { return false }
            return Double(thisWeek) / Double(lastWeek) < 0.5
        }.sorted { weeklyMentions($0, weeksAgo: 1) > weeklyMentions($1, weeksAgo: 1) }
    }

    var body: some View {
        NavigationStack {
            List {
                radarSection(
                    title: "看多共識",
                    icon: "arrow.up.circle.fill",
                    color: .green,
                    stocks: bullishConsensus,
                    subtitle: { stock in
                        let score = stock.sentimentScore.map { String(format: "%.0f%%", $0 * 100) } ?? ""
                        return "看多 \(score) · \(stock.totalMentions) 次提及"
                    }
                )
                radarSection(
                    title: "看空共識",
                    icon: "arrow.down.circle.fill",
                    color: .red,
                    stocks: bearishConsensus,
                    subtitle: { stock in
                        let score = stock.sentimentScore.map { String(format: "%.0f%%", (1 - $0) * 100) } ?? ""
                        return "看空 \(score) · \(stock.totalMentions) 次提及"
                    }
                )
                radarSection(
                    title: "本週暴紅",
                    icon: "flame.fill",
                    color: .orange,
                    stocks: hotThisWeek,
                    subtitle: { stock in
                        let tw = weeklyMentions(stock, weeksAgo: 0)
                        let lw = weeklyMentions(stock, weeksAgo: 1)
                        let ratio = lw > 0 ? String(format: "+%.0f%%", (Double(tw) / Double(lw) - 1) * 100) : "新上榜"
                        return "本週 \(tw) 次 \(ratio)"
                    }
                )
                radarSection(
                    title: "本週降溫",
                    icon: "snowflake",
                    color: .blue,
                    stocks: coolingThisWeek,
                    subtitle: { stock in
                        let tw = weeklyMentions(stock, weeksAgo: 0)
                        let lw = weeklyMentions(stock, weeksAgo: 1)
                        let ratio = lw > 0 ? String(format: "%.0f%%", Double(tw) / Double(lw) * 100) : "0%"
                        return "本週 \(tw) 次（上週 \(lw) 次，剩 \(ratio)）"
                    }
                )
            }
            .listStyle(.insetGrouped)
            .navigationTitle("投資雷達")
        }
    }

    @ViewBuilder
    private func radarSection(
        title: String,
        icon: String,
        color: Color,
        stocks: [StockEntry],
        subtitle: @escaping (StockEntry) -> String
    ) -> some View {
        Section {
            if stocks.isEmpty {
                Text("目前無符合條件的股票")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(stocks.prefix(10)) { stock in
                    NavigationLink {
                        StockDetailView(stock: stock)
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
