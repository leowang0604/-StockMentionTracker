import SwiftUI

struct VideoDetailView: View {
    let videoID: String

    @Environment(AppState.self) private var appState
    @Environment(DataService.self) private var dataService
    @Environment(\.dismiss) private var dismiss
    @State private var expandedIDs = Set<String>()

    private var video: VideoScanned? {
        dataService.video(withID: videoID)
    }

    private var stockEntries: [StockEntry] {
        guard let video else { return [] }
        return dataService.stockEntries(for: video)
    }

    private var isVideoInSelectedRange: Bool {
        guard let date = video?.parsedDate else { return false }
        return date >= appState.cutoffDate
    }

    var body: some View {
        Group {
            if let video {
                List {
                    // ── Header ────────────────────────────────────────────
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 6) {
                                Image(systemName: video.sourceIcon)
                                    .foregroundStyle(video.isYouTube ? .red : .purple)
                                Text(video.channel)
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Text(video.title).font(.headline)
                            Label(video.dateText, systemImage: "calendar")
                                .font(.caption).foregroundStyle(.secondary)
                            Label(
                                "分析方式：\(video.analysisSourceDisplay)",
                                systemImage: video.analysisSourceSymbol
                            )
                            .font(.caption)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(analysisSourceBG(for: video), in: Capsule())
                        }
                        .padding(.vertical, 4)
                    }

                    // ── Stocks ────────────────────────────────────────────
                    Section("提及股票（\(stockEntries.count) 支）") {
                        if stockEntries.isEmpty {
                            Text("此影片未偵測到股票提及")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            ForEach(stockEntries) { stock in
                                VideoStockRow(
                                    stock: stock,
                                    isExpanded: expandedIDs.contains(stock.id),
                                    onToggle: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            if expandedIDs.contains(stock.id) {
                                                expandedIDs.remove(stock.id)
                                            } else {
                                                expandedIDs.insert(stock.id)
                                            }
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "影片已不在最新資料中",
                    systemImage: "arrow.clockwise",
                    description: Text("返回內容清單查看更新後的資料")
                )
            }
        }
        .navigationTitle("影片詳情")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            if let url = video?.externalURL {
                ToolbarItem(placement: .automatic) {
                    Link(destination: url) {
                        Image(systemName: "play.circle")
                    }
                }
            }
        }
        .onChange(of: appState.selectedDays, initial: true) { _, _ in
            dismissIfOutsideSelectedRange()
        }
        .onChange(of: dataService.scanResult.updatedAt) { _, _ in
            dismissIfOutsideSelectedRange()
        }
    }

    private func dismissIfOutsideSelectedRange() {
        if video == nil || !isVideoInSelectedRange {
            dismiss()
        }
    }

    private func analysisSourceBG(for video: VideoScanned) -> Color {
        switch video.analysisSource {
        case "whisper":  return .blue.opacity(0.12)
        case "captions": return .teal.opacity(0.12)
        default:         return .gray.opacity(0.12)
        }
    }
}

// MARK: - Stock row inside video detail

private struct VideoStockRow: View {
    let stock: StockEntry
    let isExpanded: Bool
    let onToggle: () -> Void

    private var primaryContext: MentionContext? {
        stock.contexts.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(stock.code)
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text(stock.name).font(.subheadline.weight(.semibold))
                    if let context = primaryContext {
                        HStack(spacing: 6) {
                            Label(
                                context.analysisSourceDisplay,
                                systemImage: context.analysisSourceSymbol
                            )
                            if stock.contexts.count > 1 {
                                Text("\(stock.contexts.count) 次")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if stock.contexts.contains(where: { !$0.text.isEmpty }) {
                    Button(action: onToggle) {
                        Image(systemName: isExpanded
                              ? "chevron.up.circle.fill" : "chevron.down.circle")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isExpanded {
                ForEach(stock.contexts.filter { !$0.text.isEmpty }) { context in
                    let terms = mentionHighlightTerms(
                        stockName: stock.name,
                        code: stock.code,
                        matchedKeyword: context.matchedKeyword
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("提及原文")
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        if let excerpt = mentionExcerpt(context.text, terms: terms) {
                            Text(highlightedMentionText(
                                "…\(excerpt)…",
                                terms: terms
                            ))
                            .font(.caption)
                            .padding(10)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        } else {
                            Text("此筆舊資料找不到對應的原文命中詞，等待重新掃描更新。")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(10)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
