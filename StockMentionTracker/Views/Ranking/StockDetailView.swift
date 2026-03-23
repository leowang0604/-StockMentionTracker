import SwiftUI

struct StockDetailView: View {
    let rankingItem: StockRankingItem

    @State private var sourceFilter: SourceDetailFilter = .all

    enum SourceDetailFilter: String, CaseIterable {
        case all = "全部"
        case youtube = "YouTube"
        case podcast = "Podcast"
    }

    private var filteredMentions: [MentionInfo] {
        switch sourceFilter {
        case .all:
            return rankingItem.mentions
        case .youtube:
            return rankingItem.mentions.filter { $0.sourceType == SourceType.youtube.rawValue }
        case .podcast:
            return rankingItem.mentions.filter {
                $0.sourceType == SourceType.applePodcast.rawValue ||
                $0.sourceType == SourceType.spotify.rawValue
            }
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(rankingItem.stockName)
                                .font(.title2.bold())
                            Text(rankingItem.stockCode)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text("總提及次數：\(rankingItem.totalMentions) 次")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("涵蓋來源：\(rankingItem.sourceCount) 個")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(rankingItem.analysisSourceIcons)
                        .font(.title2)
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker("篩選", selection: $sourceFilter) {
                    ForEach(SourceDetailFilter.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)

            Section("提及紀錄（\(filteredMentions.count) 筆）") {
                if filteredMentions.isEmpty {
                    Text("此來源類型無提及紀錄")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(filteredMentions) { mention in
                        MentionRowView(mention: mention)
                    }
                }
            }
        }
        .navigationTitle(rankingItem.stockName)
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
    }
}

// MARK: - Mention Row View

struct MentionRowView: View {
    let mention: MentionInfo
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: sourceIcon)
                    .font(.caption)
                    .foregroundStyle(sourceColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mention.sourceName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(mention.dateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 3) {
                    Text(mention.analysisSourceIcon)
                    Text(mention.analysisSourceDisplay)
                        .font(.caption2)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(analysisSourceColor.opacity(0.15), in: Capsule())
                .foregroundStyle(analysisSourceColor)
            }

            Text(mention.episodeTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : 1)

            if !mention.context.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
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
                            Text("…\(mention.context)…")
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

    private var sourceIcon: String {
        switch mention.sourceType {
        case SourceType.youtube.rawValue: return "play.rectangle.fill"
        case SourceType.applePodcast.rawValue: return "mic.fill"
        case SourceType.spotify.rawValue: return "music.note"
        default: return "antenna.radiowaves.left.and.right"
        }
    }

    private var sourceColor: Color {
        switch mention.sourceType {
        case SourceType.youtube.rawValue: return .red
        case SourceType.applePodcast.rawValue: return .purple
        case SourceType.spotify.rawValue: return .green
        default: return Color.accentColor
        }
    }

    private var analysisSourceColor: Color {
        mention.analysisSource == "transcript" ? .blue : .gray
    }
}
