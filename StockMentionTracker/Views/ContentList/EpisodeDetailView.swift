import SwiftUI

struct EpisodeDetailView: View {
    let episode: EpisodeInfo
    let mentions: [MentionInfo]

    @State private var expandedMentions = Set<String>()

    private var sortedMentions: [MentionInfo] {
        mentions.sorted { $0.stockCode < $1.stockCode }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: episode.sourceTypeEnum.icon)
                            .foregroundStyle(sourceColor(for: episode.sourceTypeEnum))
                        Text(episode.sourceName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(episode.title).font(.headline)

                    Label(episode.publishedDateText, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Text(episode.analysisSourceIcon)
                        Text("分析方式：\(episode.analysisSourceDisplay)")
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(analysisSourceBG(for: episode.analysisSource), in: Capsule())
                }
                .padding(.vertical, 4)
            }

            Section("提及股票（\(sortedMentions.count) 支）") {
                if sortedMentions.isEmpty {
                    Text("此集數未偵測到股票提及")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(sortedMentions) { mention in
                        EpisodeMentionRow(
                            mention: mention,
                            isExpanded: expandedMentions.contains(mention.id),
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedMentions.contains(mention.id) {
                                        expandedMentions.remove(mention.id)
                                    } else {
                                        expandedMentions.insert(mention.id)
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle("集數詳細")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            if let url = episode.externalURL {
                ToolbarItem(placement: .automatic) {
                    Link(destination: url) {
                        Image(systemName: "play.circle")
                    }
                }
            }
        }
    }

    private func sourceColor(for type: SourceType) -> Color {
        switch type {
        case .youtube: return .red
        case .applePodcast: return .purple
        case .spotify: return .green
        }
    }

    private func analysisSourceBG(for source: String) -> Color {
        source == "transcript" ? .blue.opacity(0.12) : .gray.opacity(0.12)
    }
}

// MARK: - Episode Mention Row

private struct EpisodeMentionRow: View {
    let mention: MentionInfo
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(mention.stockCode)
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text(mention.stockName).font(.subheadline.weight(.semibold))
                    Text(mention.analysisSourceIcon + " " + mention.analysisSourceDisplay)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !mention.context.isEmpty {
                    Button(action: onToggle) {
                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isExpanded && !mention.context.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("提及原文")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("…\(mention.context)…")
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .padding(10)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.vertical, 2)
    }
}
