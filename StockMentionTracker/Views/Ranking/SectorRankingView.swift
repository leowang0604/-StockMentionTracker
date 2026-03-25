import SwiftUI

struct SectorRankingView: View {
    @Environment(AppState.self)    private var appState
    @Environment(DataService.self) private var dataService

    @State private var marketFilter = "all"   // "all" | "TW" | "US"

    private var filteredSectors: [SectorEntry] {
        @Bindable var appState = appState
        let cutoff = appState.cutoffDate

        // Re-compute sector totals based on the date-filtered stock mentions
        let stocksByCode: [String: StockEntry] = Dictionary(
            dataService.scanResult.stocksRanking.compactMap { stock -> (String, StockEntry)? in
                let ctxs = stock.contexts.filter { ($0.parsedDate ?? .distantPast) >= cutoff }
                guard !ctxs.isEmpty else { return nil }
                return (stock.code, StockEntry(
                    code: stock.code, name: stock.name,
                    market: stock.market, sector: stock.sector,
                    totalMentions: ctxs.count, contexts: ctxs
                ))
            },
            uniquingKeysWith: { first, _ in first }
        )

        // Rebuild sectors from date-filtered stocks
        var sectorsMap: [String: (entry: SectorEntry, mentions: Int)] = [:]
        for (_, stock) in stocksByCode {
            guard let sector = stock.sector else { continue }
            let market = stock.market ?? "TW"
            let key = "\(market)_\(sector)"
            if var existing = sectorsMap[key] {
                let newCodes = existing.entry.stockCodes + [stock.code]
                existing.entry = SectorEntry(
                    sector: sector, market: market,
                    totalMentions: existing.entry.totalMentions + stock.totalMentions,
                    stockCodes: newCodes
                )
                existing.mentions += stock.totalMentions
                sectorsMap[key] = existing
            } else {
                sectorsMap[key] = (
                    SectorEntry(sector: sector, market: market,
                                totalMentions: stock.totalMentions,
                                stockCodes: [stock.code]),
                    stock.totalMentions
                )
            }
        }

        return sectorsMap.values
            .map(\.entry)
            .sorted { $0.totalMentions > $1.totalMentions }
            .filter { marketFilter == "all" || $0.market == marketFilter }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("市場", selection: $marketFilter) {
                    Text("全部").tag("all")
                    Text("🇹🇼 台股").tag("TW")
                    Text("🇺🇸 美股").tag("US")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                if filteredSectors.isEmpty {
                    ContentUnavailableView {
                        Label("尚無族群資料", systemImage: "square.grid.2x2")
                    } description: {
                        Text("需要掃描結果含有族群分類資訊")
                    }
                } else {
                    List {
                        ForEach(Array(filteredSectors.enumerated()), id: \.element.id) { index, sector in
                            NavigationLink {
                                SectorDetailView(sector: sector)
                            } label: {
                                SectorRowView(rank: index + 1, sector: sector)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("族群排行榜")
        }
    }
}

// MARK: - Sector Row

struct SectorRowView: View {
    let rank: Int
    let sector: SectorEntry

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(rankColor)
                .frame(width: 32, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if !sector.marketFlag.isEmpty {
                        Text(sector.marketFlag).font(.caption)
                    }
                    Text(sector.sector).font(.headline)
                }
                Text("\(sector.stockCodes.count) 支個股")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(sector.totalMentions)")
                    .font(.title2.bold().monospacedDigit())
                Text("次提及")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var rankColor: Color {
        switch rank {
        case 1: return .yellow
        case 2: return Color(white: 0.7)
        case 3: return .orange
        default: return .secondary
        }
    }
}

// MARK: - Sector Detail

struct SectorDetailView: View {
    let sector: SectorEntry
    @Environment(DataService.self) private var dataService
    @Environment(AppState.self)    private var appState

    private var stocksInSector: [StockEntry] {
        @Bindable var appState = appState
        let cutoff = appState.cutoffDate
        let codes = Set(sector.stockCodes)
        return dataService.scanResult.stocksRanking
            .filter { codes.contains($0.code) }
            .compactMap { stock -> StockEntry? in
                let ctxs = stock.contexts.filter { ($0.parsedDate ?? .distantPast) >= cutoff }
                guard !ctxs.isEmpty else { return nil }
                return StockEntry(
                    code: stock.code, name: stock.name,
                    market: stock.market, sector: stock.sector,
                    totalMentions: ctxs.count, contexts: ctxs
                )
            }
            .sorted { $0.totalMentions > $1.totalMentions }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if !sector.marketFlag.isEmpty {
                                Text(sector.marketFlag)
                            }
                            Text(sector.sector).font(.title2.bold())
                        }
                        Text("族群總提及：\(sector.totalMentions) 次")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("\(sector.stockCodes.count) 支個股")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section("個股排行") {
                ForEach(Array(stocksInSector.enumerated()), id: \.element.id) { index, stock in
                    NavigationLink {
                        StockDetailView(stock: stock)
                    } label: {
                        RankingRowView(rank: index + 1, stock: stock)
                    }
                }
            }
        }
        .navigationTitle(sector.sector)
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
    }
}
