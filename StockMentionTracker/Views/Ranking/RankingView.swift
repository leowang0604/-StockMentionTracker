import SwiftUI

struct RankingView: View {
    @Environment(AppState.self) private var appState
    @Environment(DataService.self) private var dataService

    @State private var sourceFilter: SourceFilterOption = .all
    @State private var searchText = ""
    @State private var showErrorAlert = false

    enum SourceFilterOption: String, CaseIterable {
        case all = "全部"
        case youtube = "YouTube"
        case podcast = "Podcast"
    }

    private var filteredMentions: [MentionInfo] {
        var mentions = dataService.scanResult.mentions.filter {
            $0.mentionedDate >= appState.cutoffDate
        }
        switch sourceFilter {
        case .all: break
        case .youtube:
            mentions = mentions.filter { $0.sourceType == SourceType.youtube.rawValue }
        case .podcast:
            mentions = mentions.filter {
                $0.sourceType == SourceType.applePodcast.rawValue ||
                $0.sourceType == SourceType.spotify.rawValue
            }
        }
        return mentions
    }

    private var rankingItems: [StockRankingItem] {
        let grouped = Dictionary(grouping: filteredMentions) { $0.stockCode }
        return grouped.compactMap { (code, mentions) -> StockRankingItem? in
            guard let first = mentions.first else { return nil }
            let sourceNames = Set(mentions.map { $0.sourceName })
            let analysisSources = Set(mentions.map { $0.analysisSource })
            let lastDate = mentions.map { $0.mentionedDate }.max() ?? Date()
            return StockRankingItem(
                id: code,
                stockCode: code,
                stockName: first.stockName,
                totalMentions: mentions.count,
                sourceCount: sourceNames.count,
                lastMentionedAt: lastDate,
                analysisSources: analysisSources,
                mentions: mentions.sorted { $0.mentionedDate > $1.mentionedDate }
            )
        }
        .sorted { $0.totalMentions > $1.totalMentions }
        .filter {
            searchText.isEmpty ||
            $0.stockName.contains(searchText) ||
            $0.stockCode.contains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar

                if rankingItems.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(Array(rankingItems.enumerated()), id: \.element.id) { index, item in
                            NavigationLink {
                                StockDetailView(rankingItem: item)
                            } label: {
                                RankingRowView(rank: index + 1, item: item)
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

    private var filterBar: some View {
        @Bindable var appState = appState
        return VStack(spacing: 0) {
            Picker("來源類型", selection: $sourceFilter) {
                ForEach(SourceFilterOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            HStack(spacing: 10) {
                Text("最近")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $appState.selectedDays, in: 7...90, step: 1)
                Text("\(Int(appState.selectedDays)) 天")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary)
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()
        }
    }

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

// MARK: - Ranking Row View

struct RankingRowView: View {
    let rank: Int
    let item: StockRankingItem

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(rankColor)
                .frame(width: 32, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.stockName)
                        .font(.headline)
                    Text(item.stockCode)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    Text(item.analysisSourceIcons)
                        .font(.caption)
                }

                HStack(spacing: 8) {
                    Label("\(item.sourceCount) 個來源", systemImage: "antenna.radiowaves.left.and.right")
                    Text("·")
                    Text(item.lastMentionedText)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(item.totalMentions)")
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
