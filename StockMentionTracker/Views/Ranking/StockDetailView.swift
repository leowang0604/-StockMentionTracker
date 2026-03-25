import SwiftUI

struct StockDetailView: View {
    let stock: StockEntry

    @Environment(DataService.self) private var dataService
    @Environment(AppState.self)    private var appState

    @State private var expandedIDs = Set<String>()

    private var sectorPeers: [StockEntry] {
        guard let sector = stock.sector else { return [] }
        @Bindable var appState = appState
        let cutoff = appState.cutoffDate
        return dataService.scanResult.stocksRanking
            .filter { $0.sector == sector && $0.code != stock.code }
            .compactMap { s -> StockEntry? in
                let ctxs = s.contexts.filter { ($0.parsedDate ?? .distantPast) >= cutoff }
                guard !ctxs.isEmpty else { return nil }
                return StockEntry(code: s.code, name: s.name,
                                  market: s.market, sector: s.sector,
                                  totalMentions: ctxs.count, contexts: ctxs)
            }
            .sorted { $0.totalMentions > $1.totalMentions }
    }

    var body: some View {
        List {
            // ── Header ────────────────────────────────────────────────────
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if !stock.marketLabel.isEmpty {
                                Text(stock.marketLabel)
                            }
                            Text(stock.name).font(.title2.bold())
                            Text(stock.code)
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let sector = stock.sector {
                            Text(sector)
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.blue.opacity(0.12), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                        Text("提及次數：\(stock.totalMentions) 次")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("涵蓋來源：\(stock.channelCount) 個")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(stock.analysisSourceSymbols, id: \.self) {
                            Image(systemName: $0).font(.title2)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // ── Sector peers ──────────────────────────────────────────────
            if !sectorPeers.isEmpty {
                Section("同族群個股") {
                    // Current stock (highlighted)
                    HStack {
                        Text(stock.name).font(.subheadline.bold())
                        Text(stock.code).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(stock.totalMentions) 次")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(Color.accentColor.opacity(0.1))

                    ForEach(Array(sectorPeers.enumerated()), id: \.element.id) { _, peer in
                        NavigationLink {
                            StockDetailView(stock: peer)
                        } label: {
                            HStack {
                                Text(peer.name).font(.subheadline)
                                Text(peer.code).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(peer.totalMentions) 次")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            // ── Mention list ──────────────────────────────────────────────
            Section("提及紀錄（\(stock.contexts.count) 筆）") {
                if stock.contexts.isEmpty {
                    Text("無提及紀錄")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(stock.contexts) { ctx in
                        ContextRowView(
                            context: ctx,
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
        .navigationTitle(stock.name)
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
    }
}

// MARK: - Context Row

struct ContextRowView: View {
    let context: MentionContext
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Channel + date + analysis source badge
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.channel ?? "未知來源")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(context.dateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 3) {
                    Image(systemName: context.analysisSourceSymbol)
                    Text(context.analysisSourceDisplay)
                        .font(.caption2)
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(analysisColor.opacity(0.15), in: Capsule())
                .foregroundStyle(analysisColor)
            }

            // Video title
            Text(context.video)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : 1)

            // Context text (expandable)
            if !context.text.isEmpty {
                Button(action: onToggle) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("提及內容")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if isExpanded {
                            Text("…\(context.text)…")
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var analysisColor: Color {
        switch context.analysisSource {
        case "whisper":  return .blue
        case "captions": return .teal
        default:         return .gray
        }
    }

}
