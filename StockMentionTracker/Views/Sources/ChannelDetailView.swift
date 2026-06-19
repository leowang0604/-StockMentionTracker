import SwiftUI

struct ChannelDetailView: View {
    let channelName: String

    @Environment(DataService.self) private var dataService
    @Environment(AppState.self)    private var appState

    @State private var sortByDate = false

    private var cutoff: Date { appState.cutoffDate }

    private var stocks: [StockEntry] {
        let raw = dataService.stocksByChannel(channelName, cutoff: cutoff)
        if sortByDate {
            return raw.sorted {
                ($0.contexts.compactMap(\.parsedDate).max() ?? .distantPast) >
                ($1.contexts.compactMap(\.parsedDate).max() ?? .distantPast)
            }
        }
        return raw  // default: by mention count
    }

    private var episodes: [VideoScanned] {
        dataService.episodesByChannel(channelName, cutoff: cutoff)
    }

    var body: some View {
        List {
            // ── Stocks ────────────────────────────────────────────────────
            Section {
                if stocks.isEmpty {
                    Text("此時間範圍內無股票提及")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(stocks) { stock in
                        NavigationLink {
                            StockDetailView(stock: stock)
                        } label: {
                            ChannelStockRow(stock: stock)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("提及股票（\(stocks.count) 支）")
                    Spacer()
                    Button {
                        sortByDate.toggle()
                    } label: {
                        Label(sortByDate ? "最新日期" : "提及次數",
                              systemImage: sortByDate ? "calendar" : "number")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // ── Episodes ──────────────────────────────────────────────────
            Section("集數（\(episodes.count) 集）") {
                if episodes.isEmpty {
                    Text("此時間範圍內無集數")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(episodes) { episode in
                        NavigationLink {
                            VideoDetailView(videoID: episode.id)
                        } label: {
                            VideoRowView(video: episode)
                        }
                    }
                }
            }
        }
        .navigationTitle(channelName)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

// MARK: - Stock row inside channel detail

private struct ChannelStockRow: View {
    let stock: StockEntry

    private var latestDate: String? {
        guard let d = stock.contexts.compactMap(\.parsedDate).max() else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_TW")
        df.dateFormat = "M/d"
        return df.string(from: d)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if !stock.marketLabel.isEmpty {
                        Text(stock.marketLabel)
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                    Text(stock.name).font(.subheadline.weight(.semibold))
                    Text(stock.code)
                        .font(.caption).foregroundStyle(.secondary)
                    if let date = latestDate {
                        Text(date)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                SentimentCountRow(contexts: stock.contexts)
            }
            Spacer()
            Text("\(stock.totalMentions) 次")
                .font(.subheadline.bold())
                .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 2)
    }
}
