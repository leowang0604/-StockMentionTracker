import SwiftUI

struct ChannelDetailView: View {
    let channelName: String

    @Environment(DataService.self) private var dataService
    @Environment(AppState.self)    private var appState

    private var cutoff: Date { appState.cutoffDate }

    private var stocks: [StockEntry] {
        dataService.stocksByChannel(channelName, cutoff: cutoff)
    }

    private var episodes: [VideoScanned] {
        dataService.episodesByChannel(channelName, cutoff: cutoff)
    }

    var body: some View {
        List {
            // ── Stocks ────────────────────────────────────────────────────
            Section("提及股票（\(stocks.count) 支）") {
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
                            VideoDetailView(
                                video: episode,
                                stockEntries: dataService.stockEntries(for: episode)
                            )
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
