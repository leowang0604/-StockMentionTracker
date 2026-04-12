import SwiftUI

struct RankingView: View {
    @Environment(AppState.self)    private var appState
    @Environment(DataService.self) private var dataService

    @State private var searchText     = ""
    @State private var marketFilter   = "all"   // "all" | "TW" | "US"
    @State private var showErrorAlert = false

    // Filtered and date-trimmed stocks
    private var filteredStocks: [StockEntry] {
        @Bindable var appState = appState
        let cutoff = appState.cutoffDate
        return dataService.scanResult.stocksRanking
            .compactMap { stock -> StockEntry? in
                let ctxs = stock.contexts.filter { ($0.parsedDate ?? .distantPast) >= cutoff }
                guard !ctxs.isEmpty else { return nil }
                let bullish = Double(ctxs.filter { $0.sentiment == "bullish" }.count)
                let bearish = Double(ctxs.filter { $0.sentiment == "bearish" }.count)
                let signaled = bullish + bearish
                let filteredScore: Double? = signaled > 0 ? bullish / signaled : nil
                return StockEntry(
                    code: stock.code, name: stock.name,
                    market: stock.market, sector: stock.sector,
                    totalMentions: ctxs.count, contexts: ctxs,
                    sentimentScore: filteredScore, daily: nil
                )
            }
            .sorted { $0.episodeCount > $1.episodeCount }
            .filter { stock in
                let matchMarket = marketFilter == "all" || stock.market == marketFilter
                let matchSearch = searchText.isEmpty ||
                    stock.name.contains(searchText) ||
                    stock.code.contains(searchText)
                let matchETF = appState.isETFVisible(sector: stock.sector)
                return matchMarket && matchSearch && matchETF
            }
    }

    var body: some View {
        @Bindable var appState = appState
        return NavigationStack {
            VStack(spacing: 0) {
                marketPicker
                filterBar

                if filteredStocks.isEmpty {
                    emptyState
                } else {
                    List {
                        if let summary = dataService.scanResult.weeklySummary,
                           searchText.isEmpty, marketFilter == "all" {
                            let stockLookup = Dictionary(
                                uniqueKeysWithValues: dataService.scanResult.stocksRanking.map { ($0.code, $0) }
                            )
                            Section {
                                WeeklySummaryCard(summary: summary, stockLookup: stockLookup)
                            }
                        }
                        ForEach(Array(filteredStocks.enumerated()), id: \.element.id) { index, stock in
                            NavigationLink {
                                StockDetailView(stock: stock)
                            } label: {
                                RankingRowView(rank: index + 1, stock: stock)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("股票排行榜")
            .searchable(text: $searchText, prompt: "搜尋股票名稱或代號")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await dataService.fetchLatest(from: appState.dataURL) }
                    } label: {
                        if dataService.isLoading {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(dataService.isLoading)
                }
                ToolbarItem(placement: .bottomBar) {
                    let text = dataService.scanResult.updatedAt.isEmpty
                        ? ""
                        : "更新於 \(dataService.scanResult.updatedDateText)"
                    Text(text)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .alert("載入失敗", isPresented: $showErrorAlert) {
                Button("確定") { dataService.errorMessage = nil }
            } message: {
                Text(dataService.errorMessage ?? "")
            }
            .onChange(of: dataService.errorMessage) { _, error in
                showErrorAlert = error != nil
            }
        }
    }

    // MARK: - Market picker

    private var marketPicker: some View {
        Picker("市場", selection: $marketFilter) {
            Text("全部").tag("all")
            Text("台股").tag("TW")
            Text("美股").tag("US")
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        @Bindable var appState = appState
        return VStack(spacing: 0) {
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
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("尚無資料", systemImage: "chart.bar")
        } description: {
            if appState.hasDataURL {
                Text("點選右上角重新整理以載入最新掃描結果")
            } else {
                Text("請至「設定」頁面設定 GitHub Raw URL")
            }
        } actions: {
            if appState.hasDataURL {
                Button("重新整理") {
                    Task { await dataService.fetchLatest(from: appState.dataURL) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Weekly Summary Card

struct WeeklySummaryCard: View {
    let summary: WeeklySummary
    let stockLookup: [String: StockEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("市場摘要", systemImage: "sparkles")
                    .font(.subheadline.bold())
                    .foregroundStyle(.purple)
                Spacer()
                Text(generatedAtText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(summary.text)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineSpacing(4)

            if !hotStockEntries.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(hotStockEntries) { stock in
                            NavigationLink {
                                StockDetailView(stock: stock)
                            } label: {
                                Text(stock.name)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(.orange.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !summary.keyThemes.isEmpty {
                HStack(spacing: 6) {
                    ForEach(summary.keyThemes, id: \.self) { theme in
                        Text(theme)
                            .font(.caption2)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.purple.opacity(0.1), in: Capsule())
                            .foregroundStyle(.purple)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var hotStockEntries: [StockEntry] {
        summary.hotStocks.compactMap { stockLookup[$0] }
    }

    private var generatedAtText: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        guard let date = f.date(from: summary.generatedAt) else { return "" }
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_TW")
        df.dateFormat = "M/d 由 AI 生成"
        return df.string(from: date)
    }
}

// MARK: - Ranking Row

struct RankingRowView: View {
    let rank: Int
    let stock: StockEntry

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(rankColor)
                .frame(width: 32, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if !stock.marketLabel.isEmpty {
                        Text(stock.marketLabel).font(.caption)
                    }
                    Text(stock.name).font(.headline)
                    Text(stock.code)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    ForEach(stock.analysisSourceSymbols, id: \.self) {
                        Image(systemName: $0).font(.caption)
                    }
                }
                HStack(spacing: 6) {
                    if let sector = stock.sector {
                        Text(sector)
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                    if !stock.sentimentLabel.isEmpty {
                        Text(stock.sentimentLabel)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(sentimentBadgeColor(stock).opacity(0.15), in: Capsule())
                            .foregroundStyle(sentimentBadgeColor(stock))
                    }
                    Label("\(stock.channelCount) 個來源",
                          systemImage: "antenna.radiowaves.left.and.right")
                    Text("·")
                    Text(stock.lastDateText)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(stock.episodeCount)")
                    .font(.title2.bold().monospacedDigit())
                Text("集提及")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("共 \(stock.totalMentions) 次")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }

    private var rankColor: Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.84, blue: 0.0)  // 金
        case 2: return Color(red: 0.75, green: 0.75, blue: 0.80) // 銀
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20) // 銅
        default: return .secondary
        }
    }

    private func sentimentBadgeColor(_ stock: StockEntry) -> Color {
        switch stock.sentimentColor {
        case "green": return .green
        case "red":   return .red
        default:      return .secondary
        }
    }
}
