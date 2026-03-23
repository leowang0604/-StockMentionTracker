import SwiftUI

struct StockDetailView: View {
    let stock: StockEntry

    @State private var expandedIDs = Set<String>()

    var body: some View {
        List {
            // ── Header ────────────────────────────────────────────────────
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(stock.name).font(.title2.bold())
                            Text(stock.code)
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text("提及次數：\(stock.totalMentions) 次")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("涵蓋來源：\(stock.channelCount) 個")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(stock.analysisSourceIcons).font(.title2)
                }
                .padding(.vertical, 4)
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
                    Text(context.analysisSourceIcon)
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
