import SwiftUI

// MARK: - Channel Management View

struct ChannelManagementView: View {
    @Environment(AppState.self) private var appState

    @State private var sourcesConfig: SourcesConfig = SourcesConfig(sources: [])
    @State private var currentSHA: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadErrorMessage: String?
    @State private var showingAddChannel = false
    @State private var channelToDelete: ChannelSource?
    @State private var showDeleteAlert = false
    @State private var isSaving = false
    @State private var saveSuccess = false
    @State private var needsResave = false

    var body: some View {
        mainContent
            .navigationTitle("頻道管理")
            .toolbar {
                if appState.hasGitHubConfig {
                    ToolbarItem(placement: .automatic) {
                        Button { showingAddChannel = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddChannel) {
                AddChannelView { newChannel in addChannel(newChannel) }
            }
            .alert("確認刪除", isPresented: $showDeleteAlert, presenting: channelToDelete) { ch in
                Button("刪除", role: .destructive) { deleteChannel(ch) }
                Button("取消", role: .cancel) {}
            } message: { ch in
                Text("確定要從掃描清單移除「\(ch.name)」嗎？")
            }
            .alert("發生錯誤", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("確定") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                if appState.hasGitHubConfig { await loadChannels() }
            }
            .onChange(of: appState.hasGitHubConfig) { _, hasConfig in
                if hasConfig { Task { await loadChannels() } }
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        if !appState.hasGitHubConfig {
            noConfigState
        } else if isLoading {
            ProgressView("載入頻道清單…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            channelList
        }
    }

    // MARK: - Channel List

    private var channelList: some View {
        List {
            if let loadErrorMessage, sourcesConfig.sources.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("無法載入頻道清單", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(loadErrorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("請先到設定頁確認 GitHub Repo 與 Personal Access Token，再按重新載入。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else if sourcesConfig.sources.isEmpty {
                Text("尚無頻道，點選右上角 + 新增")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(sourcesConfig.sources) { channel in
                    ChannelRowView(
                        channel: channel,
                        onToggle: { active in toggleActive(channel: channel, active: active) },
                        onExtractionModeChange: { mode in setExtractionMode(channel: channel, mode: mode) }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            channelToDelete = channel
                            showDeleteAlert = true
                        } label: {
                            Label("刪除", systemImage: "trash")
                        }
                    }
                }
            }

            Section {
                Button {
                    Task { await loadChannels() }
                } label: {
                    Label("重新載入", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(isLoading)
            } footer: {
                Text("修改會儲存到 GitHub，GitHub Actions 每日自動掃描。\nApple Podcast 填入數字 ID（Apple Podcast 連結中的 id 後面的數字）。\nSpotify 需在 GitHub Secrets 設定 SPOTIFY_CLIENT_ID / SPOTIFY_CLIENT_SECRET。")
            }
        }
        .overlay(alignment: .bottom) {
            if isSaving {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("儲存中…").font(.caption)
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding()
            } else if saveSuccess {
                Label("已儲存", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding()
            }
        }
    }

    // MARK: - No Config State

    private var noConfigState: some View {
        ContentUnavailableView {
            Label("未設定 GitHub", systemImage: "gear")
        } description: {
            Text("請至「設定」頁面填入 GitHub Repo 和 Personal Access Token")
        }
    }

    // MARK: - Actions

    private func loadChannels() async {
        isLoading = true
        errorMessage = nil
        do {
            let (config, sha) = try await GitHubService.shared.fetchSources(
                repo: appState.githubRepo, pat: appState.githubPAT
            )
            sourcesConfig = config
            currentSHA = sha
            loadErrorMessage = nil
        } catch {
            let message = error.localizedDescription
            loadErrorMessage = message
            errorMessage = message
        }
        isLoading = false
    }

    private func saveChannels() async {
        guard !isSaving else {
            needsResave = true
            return
        }
        isSaving = true
        needsResave = false
        saveSuccess = false
        do {
            do {
                try await GitHubService.shared.saveSources(
                    config: sourcesConfig,
                    repo: appState.githubRepo,
                    pat: appState.githubPAT,
                    sha: currentSHA
                )
            } catch {
                // SHA conflict — refresh and retry once
                let (_, freshSHA) = try await GitHubService.shared.fetchSources(
                    repo: appState.githubRepo, pat: appState.githubPAT
                )
                currentSHA = freshSHA
                try await GitHubService.shared.saveSources(
                    config: sourcesConfig,
                    repo: appState.githubRepo,
                    pat: appState.githubPAT,
                    sha: currentSHA
                )
            }
            let (_, sha) = try await GitHubService.shared.fetchSources(
                repo: appState.githubRepo, pat: appState.githubPAT
            )
            currentSHA = sha
            saveSuccess = true
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            saveSuccess = false
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
        if needsResave {
            await saveChannels()
        }
    }

    private func addChannel(_ channel: ChannelSource) {
        let isDuplicate = sourcesConfig.sources.contains {
            $0.identifier == channel.identifier && $0.type == channel.type
        }
        guard !isDuplicate else {
            errorMessage = "「\(channel.name)」已在清單中（ID 重複）"
            return
        }
        sourcesConfig.sources.append(channel)
        Task { await saveChannels() }
    }

    private func deleteChannel(_ channel: ChannelSource) {
        sourcesConfig.sources.removeAll { $0.id == channel.id }
        Task { await saveChannels() }
    }

    private func toggleActive(channel: ChannelSource, active: Bool) {
        if let idx = sourcesConfig.sources.firstIndex(where: { $0.id == channel.id }) {
            sourcesConfig.sources[idx].active = active
            Task { await saveChannels() }
        }
    }

    private func setExtractionMode(channel: ChannelSource, mode: String?) {
        if let idx = sourcesConfig.sources.firstIndex(where: { $0.id == channel.id }) {
            sourcesConfig.sources[idx].extractionMode = mode
            Task { await saveChannels() }
        }
    }
}

// MARK: - Channel Row View

struct ChannelRowView: View {
    let channel: ChannelSource
    let onToggle: (Bool) -> Void
    let onExtractionModeChange: (String?) -> Void

    @State private var isActive: Bool
    @State private var extractionMode: String?

    init(channel: ChannelSource,
         onToggle: @escaping (Bool) -> Void,
         onExtractionModeChange: @escaping (String?) -> Void) {
        self.channel = channel
        self.onToggle = onToggle
        self.onExtractionModeChange = onExtractionModeChange
        self._isActive = State(initialValue: channel.active)
        self._extractionMode = State(initialValue: channel.extractionMode)
    }

    var body: some View {
        NavigationLink {
            ChannelDetailView(channelName: channel.name)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconBackground)
                        .frame(width: 44, height: 44)
                    Image(systemName: channel.sourceType.icon)
                        .foregroundStyle(.white)
                        .font(.title3)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.name)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(channel.sourceType.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(channel.identifier)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Extraction mode menu
                Menu {
                    Button {
                        extractionMode = nil
                        onExtractionModeChange(nil)
                    } label: {
                        Label("全域預設", systemImage: extractionMode == nil ? "checkmark" : "")
                    }
                    Button {
                        extractionMode = "keyword"
                        onExtractionModeChange("keyword")
                    } label: {
                        Label("僅關鍵字", systemImage: extractionMode == "keyword" ? "checkmark" : "")
                    }
                    Button {
                        extractionMode = "auto"
                        onExtractionModeChange("auto")
                    } label: {
                        Label("關鍵字 + AI", systemImage: extractionMode == "auto" ? "checkmark" : "")
                    }
                    Button {
                        extractionMode = "gemini"
                        onExtractionModeChange("gemini")
                    } label: {
                        Label("僅 AI", systemImage: extractionMode == "gemini" ? "checkmark" : "")
                    }
                } label: {
                    Text(extractionModeLabel)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(extractionModeColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(extractionModeColor)
                }
                .buttonStyle(.plain)

                Toggle("", isOn: $isActive)
                    .labelsHidden()
                    .onChange(of: isActive) { _, newValue in
                        onToggle(newValue)
                    }
            }
            .padding(.vertical, 4)
            .opacity(isActive ? 1.0 : 0.6)
        }
    }

    private var extractionModeLabel: String {
        switch extractionMode {
        case "keyword": return "關鍵字"
        case "auto":    return "關鍵字+AI"
        case "gemini":  return "僅AI"
        default:        return "預設"
        }
    }

    private var extractionModeColor: Color {
        switch extractionMode {
        case "auto":   return .purple
        case "gemini": return .blue
        default:       return .secondary
        }
    }

    private var iconBackground: Color {
        switch channel.sourceType {
        case .youtube: return .red
        case .applePodcast: return .purple
        case .spotify: return .green
        }
    }
}
