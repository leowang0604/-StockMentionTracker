import SwiftUI

struct VideoDetailView: View {
    let video: VideoScanned
    let stockEntries: [StockEntry]

    @State private var expandedIDs = Set<String>()

    var body: some View {
        List {
            // ── Header ────────────────────────────────────────────────────
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
                    Label("分析方式：\(video.analysisSourceDisplay)", systemImage: video.analysisSourceSymbol)
                        .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(analysisSourceBG, in: Capsule())
                }
                .padding(.vertical, 4)
            }

            // ── Stocks ────────────────────────────────────────────────────
            Section("提及股票（\(stockEntries.count) 支）") {
                if stockEntries.isEmpty {
                    Text("此影片未偵測到股票提及")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(stockEntries) { stock in
                        ForEach(stock.contexts) { ctx in
                            VideoStockRow(
                                stock: stock,
                                context: ctx,
                                highlightTerms: highlightTerms(for: stock, context: ctx),
                                isExpanded: expandedIDs.contains(ctx.id),
                                onToggle: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if expandedIDs.contains(ctx.id) {
                                            expandedIDs.remove(ctx.id)
                                        } else {
                                            expandedIDs.insert(ctx.id)
                                        }
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("影片詳情")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
#endif
        .toolbar {
            if let url = video.externalURL {
                ToolbarItem(placement: .automatic) {
                    Link(destination: url) {
                        Image(systemName: "play.circle")
                    }
                }
            }
        }
    }

    private var analysisSourceBG: Color {
        switch video.analysisSource {
        case "whisper":  return .blue.opacity(0.12)
        case "captions": return .teal.opacity(0.12)
        default:         return .gray.opacity(0.12)
        }
    }

    private func highlightTerms(for stock: StockEntry, context: MentionContext) -> [String] {
        mentionHighlightTerms(
            stockName: stock.name,
            code: stock.code,
            matchedKeyword: context.matchedKeyword
        )
    }
}

// MARK: - Stock row inside video detail

private struct VideoStockRow: View {
    let stock: StockEntry
    let context: MentionContext
    let highlightTerms: [String]
    let isExpanded: Bool
    let onToggle: () -> Void

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
                    Label(context.analysisSourceDisplay, systemImage: context.analysisSourceSymbol)
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Spacer()

                if !context.text.isEmpty {
                    Button(action: onToggle) {
                        Image(systemName: isExpanded
                              ? "chevron.up.circle.fill" : "chevron.down.circle")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isExpanded && !context.text.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("提及原文")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text(highlightedMentionText("…\(context.text)…", terms: highlightTerms))
                        .font(.caption)
                        .padding(10)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.vertical, 2)
    }
}
