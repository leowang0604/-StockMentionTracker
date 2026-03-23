import SwiftUI

struct ContentListView: View {
    @Environment(AppState.self) private var appState
    @Environment(DataService.self) private var dataService

    @State private var typeFilter: ContentTypeFilter = .all
    @State private var searchText = ""

    enum ContentTypeFilter: String, CaseIterable {
        case all = "全部"
        case youtube = "YouTube"
        case podcast = "Podcast"
    }

    private var filteredEpisodes: [EpisodeInfo] {
        var episodes = dataService.scanResult.episodes.filter {
            !$0.mentionedStocks.isEmpty && $0.publishedDate >= appState.cutoffDate
        }

        switch typeFilter {
        case .all: break
        case .youtube:
            episodes = episodes.filter { $0.sourceType == SourceType.youtube.rawValue }
        case .podcast:
            episodes = episodes.filter {
                $0.sourceType == SourceType.applePodcast.rawValue ||
                $0.sourceType == SourceType.spotify.rawValue
            }
        }

        if !searchText.isEmpty {
            episodes = episodes.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.sourceName.localizedCaseInsensitiveContains(searchText)
            }
        }

        return episodes.sorted { $0.publishedDate > $1.publishedDate }
    }

    private func mentions(for episode: EpisodeInfo) -> [MentionInfo] {
        dataService.scanResult.mentions.filter { $0.episodeId == episode.id }
    }

    var body: some View {
        @Bindable var appState = appState
        return NavigationStack {
            VStack(spacing: 0) {
                Picker("類型", selection: $typeFilter) {
                    ForEach(ContentTypeFilter.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
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

                if filteredEpisodes.isEmpty {
                    ContentUnavailableView(
                        "尚無內容",
                        systemImage: "list.bullet.rectangle",
                        description: Text("掃描結果載入後，已分析的影片會顯示在這裡")
                    )
                } else {
                    List(filteredEpisodes) { episode in
                        NavigationLink {
                            EpisodeDetailView(episode: episode, mentions: mentions(for: episode))
                        } label: {
                            EpisodeRowView(episode: episode)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("內容清單")
            .searchable(text: $searchText, prompt: "搜尋標題或節目")
        }
    }
}

// MARK: - Episode Row View

struct EpisodeRowView: View {
    let episode: EpisodeInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: episode.sourceTypeEnum.icon)
                        .font(.caption2)
                    Text(episode.sourceName)
                        .font(.caption)
                }
                .foregroundStyle(sourceColor(for: episode.sourceTypeEnum))
                Spacer()
                Text(episode.publishedDateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(episode.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)

            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Image(systemName: "chart.bar.fill").font(.caption2)
                    Text("\(episode.mentionedStocks.count) 支股票").font(.caption)
                }
                .foregroundStyle(Color.accentColor)

                Text(episode.analysisSourceIcon + episode.analysisSourceDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            if !episode.mentionedStocks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(episode.mentionedStocks.prefix(8), id: \.self) { code in
                            Text(code)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                        if episode.mentionedStocks.count > 8 {
                            Text("+\(episode.mentionedStocks.count - 8)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func sourceColor(for type: SourceType) -> Color {
        switch type {
        case .youtube: return .red
        case .applePodcast: return .purple
        case .spotify: return .green
        }
    }
}
