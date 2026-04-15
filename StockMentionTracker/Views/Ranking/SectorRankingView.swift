import SwiftUI

struct SectorRankingView: View {
    @Environment(AppState.self)    private var appState
    @Environment(DataService.self) private var dataService

    @State private var marketFilter = "all"   // "all" | "TW" | "US"
    @State private var sectorSort   = "episodes" // "episodes" | "stocks" | "date"

    private var sortLabel: String {
        switch sectorSort {
        case "stocks": return "個股數"
        case "date":   return "最新日期"
        default:       return "集數"
        }
    }

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
                    totalMentions: ctxs.count, contexts: ctxs,
                    sentimentScore: nil, daily: nil
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
            let episodes = stock.episodeCount
            if var existing = sectorsMap[key] {
                let newCodes = existing.entry.stockCodes + [stock.code]
                existing.entry = SectorEntry(
                    sector: sector, market: market,
                    totalMentions: existing.entry.totalMentions + episodes,
                    stockCodes: newCodes
                )
                existing.mentions += episodes
                sectorsMap[key] = existing
            } else {
                sectorsMap[key] = (
                    SectorEntry(sector: sector, market: market,
                                totalMentions: episodes,
                                stockCodes: [stock.code]),
                    episodes
                )
            }
        }

        let base = sectorsMap.values
            .map(\.entry)
            .filter { marketFilter == "all" || $0.market == marketFilter }
        switch sectorSort {
        case "stocks":
            return base.sorted { $0.stockCodes.count > $1.stockCodes.count }
        case "date":
            return base.sorted { a, b in
                let latestA = dataService.scanResult.stocksRanking
                    .filter { a.stockCodes.contains($0.code) }
                    .flatMap(\.contexts)
                    .compactMap(\.parsedDate).max() ?? .distantPast
                let latestB = dataService.scanResult.stocksRanking
                    .filter { b.stockCodes.contains($0.code) }
                    .flatMap(\.contexts)
                    .compactMap(\.parsedDate).max() ?? .distantPast
                return latestA > latestB
            }
        default: // episodes
            return base.sorted { $0.totalMentions > $1.totalMentions }
        }
    }

    var body: some View {
        @Bindable var appState = appState
        return NavigationStack {
            VStack(spacing: 0) {
                Picker("市場", selection: $marketFilter) {
                    Text("全部").tag("all")
                    Text("台股").tag("TW")
                    Text("美股").tag("US")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                HStack(spacing: 10) {
                    Text("最近").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $appState.selectedDays, in: 1...90, step: 1)
                    Text("\(Int(appState.selectedDays)) 天")
                        .font(.caption.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                Divider()

                if filteredSectors.isEmpty {
                    ContentUnavailableView {
                        Label("尚無族群資料", systemImage: "square.grid.2x2")
                    } description: {
                        Text("點選右上角重新整理以載入最新掃描結果")
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
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button { sectorSort = "episodes" } label: {
                            Label("集數（預設）", systemImage: sectorSort == "episodes" ? "checkmark" : "")
                        }
                        Button { sectorSort = "stocks" } label: {
                            Label("個股數", systemImage: sectorSort == "stocks" ? "checkmark" : "")
                        }
                        Button { sectorSort = "date" } label: {
                            Label("最新日期", systemImage: sectorSort == "date" ? "checkmark" : "")
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(sortLabel).font(.caption)
                        }
                    }
                }
            }
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
                    if !sector.marketLabel.isEmpty {
                        Text(sector.marketLabel).font(.caption)
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
                Text("集提及")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var rankColor: Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case 2: return Color(red: 0.75, green: 0.75, blue: 0.80)
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20)
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
                    totalMentions: ctxs.count, contexts: ctxs,
                    sentimentScore: nil, daily: nil
                )
            }
            .sorted { $0.episodeCount > $1.episodeCount }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if !sector.marketLabel.isEmpty {
                                Text(sector.marketLabel)
                            }
                            Text(sector.sector).font(.title2.bold())
                        }
                        Text("族群總提及：\(sector.totalMentions) 集")
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
