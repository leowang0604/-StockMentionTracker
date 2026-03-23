import SwiftUI

struct ContentListView: View {
    @Environment(AppState.self)    private var appState
    @Environment(DataService.self) private var dataService

    @State private var searchText = ""

    private var filteredVideos: [VideoScanned] {
        @Bindable var appState = appState
        let cutoff = appState.cutoffDate
        return dataService.scanResult.videosScanned
            .filter { !$0.stocksFound.isEmpty && ($0.parsedDate ?? .distantPast) >= cutoff }
            .filter {
                searchText.isEmpty ||
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.channel.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { ($0.parsedDate ?? .distantPast) > ($1.parsedDate ?? .distantPast) }
    }

    var body: some View {
        @Bindable var appState = appState
        return NavigationStack {
            VStack(spacing: 0) {
                // Date slider
                HStack(spacing: 10) {
                    Text("最近")
                        .font(.caption).foregroundStyle(.secondary)
                    Slider(value: $appState.selectedDays, in: 7...90, step: 1)
                    Text("\(Int(appState.selectedDays)) 天")
                        .font(.caption.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                if filteredVideos.isEmpty {
                    ContentUnavailableView(
                        "尚無內容",
                        systemImage: "list.bullet.rectangle",
                        description: Text("此時間範圍內無掃描結果")
                    )
                } else {
                    List(filteredVideos) { video in
                        NavigationLink {
                            VideoDetailView(
                                video: video,
                                stockEntries: stockEntries(for: video)
                            )
                        } label: {
                            VideoRowView(video: video)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("內容清單")
            .searchable(text: $searchText, prompt: "搜尋標題或頻道")
        }
    }

    private func stockEntries(for video: VideoScanned) -> [StockEntry] {
        dataService.scanResult.stocksRanking.compactMap { stock -> StockEntry? in
            let ctxs = stock.contexts.filter { $0.video == video.title }
            guard !ctxs.isEmpty else { return nil }
            return StockEntry(
                code: stock.code, name: stock.name,
                totalMentions: ctxs.count, contexts: ctxs
            )
        }
    }
}

// MARK: - Video Row

struct VideoRowView: View {
    let video: VideoScanned

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "play.rectangle.fill")
                    .font(.caption2).foregroundStyle(.red)
                Text(video.channel)
                    .font(.caption).foregroundStyle(.red)
                Spacer()
                Text(video.dateText)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Text(video.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)

            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Image(systemName: "chart.bar.fill").font(.caption2)
                    Text("\(video.stocksFound.count) 支股票").font(.caption)
                }
                .foregroundStyle(Color.accentColor)

                Text(video.analysisSourceIcon + " " + video.analysisSourceDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            if !video.stocksFound.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(video.stocksFound.prefix(8), id: \.self) { code in
                            Text(code)
                                .font(.caption2)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                        if video.stocksFound.count > 8 {
                            Text("+\(video.stocksFound.count - 8)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
