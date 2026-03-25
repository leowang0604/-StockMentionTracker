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
                return StockEntry(
                    code: stock.code, name: stock.name,
                    market: stock.market, sector: stock.sector,
                    totalMentions: ctxs.count, contexts: ctxs
                )
            }
            .sorted { $0.totalMentions > $1.totalMentions }
            .filter { stock in
                let matchMarket = marketFilter == "all" || stock.market == marketFilter
                let matchSearch = searchText.isEmpty ||
                    stock.name.contains(searchText) ||
                    stock.code.contains(searchText)
                return matchMarket && matchSearch
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
            Text("🇹🇼 台股").tag("TW")
            Text("🇺🇸 美股").tag("US")
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
                Slider(value: $appState.selectedDays, in: 7...90, step: 1)
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
                    if !stock.marketFlag.isEmpty {
                        Text(stock.marketFlag).font(.caption)
                    }
                    Text(stock.name).font(.headline)
                    Text(stock.code)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    Text(stock.analysisSourceIcons).font(.caption)
                }
                HStack(spacing: 6) {
                    if let sector = stock.sector {
                        Text(sector)
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)
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
                Text("\(stock.totalMentions)")
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
