import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(DataService.self) private var dataService

    @State private var dataURLInput = ""
    @State private var githubRepoInput = ""
    @State private var githubPATInput = ""
    @State private var showingClearAlert = false
    @State private var sourcesConfig: SourcesConfig = SourcesConfig(sources: [], globalExtractionMode: nil)
    @State private var currentSHA: String = ""

    var body: some View {
        NavigationStack {
            Form {
                dataURLSection
                githubSection
                extractionModeSection
                etfFilterSection
                dataInfoSection
                dangerZoneSection
            }
            .navigationTitle("設定")
            .onAppear {
                dataURLInput = appState.dataURL
                githubRepoInput = appState.githubRepo
                githubPATInput = appState.githubPAT
                if appState.hasGitHubConfig {
                    Task { await loadGlobalExtractionMode() }
                }
            }
        }
    }

    private func loadGlobalExtractionMode() async {
        guard appState.hasGitHubConfig else { return }
        do {
            let (config, sha) = try await GitHubService.shared.fetchSources(
                repo: appState.githubRepo, pat: appState.githubPAT
            )
            sourcesConfig = config
            currentSHA = sha
        } catch {}
    }

    private func saveGlobalExtractionMode(_ mode: String?) async {
        guard appState.hasGitHubConfig, !currentSHA.isEmpty else { return }
        sourcesConfig.globalExtractionMode = mode
        do {
            try await GitHubService.shared.saveSources(
                config: sourcesConfig,
                repo: appState.githubRepo,
                pat: appState.githubPAT,
                sha: currentSHA
            )
            let (_, sha) = try await GitHubService.shared.fetchSources(
                repo: appState.githubRepo, pat: appState.githubPAT
            )
            currentSHA = sha
        } catch {}
    }

    // MARK: - Data URL Section

    private var dataURLSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                TextField("https://raw.githubusercontent.com/...", text: $dataURLInput)
                    .font(.caption.monospaced())
                    .autocorrectionDisabled()
#if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
#endif

                let urlChanged = dataURLInput != appState.dataURL
                Button("儲存") {
                    appState.dataURL = dataURLInput
                }
                .buttonStyle(.bordered)
                .font(.caption)
                .disabled(!urlChanged)
                .tint(urlChanged ? .accentColor : .secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("GitHub Raw URL（資料來源）")
        } footer: {
            Text("格式：https://raw.githubusercontent.com/username/repo/main/data/latest.json")
        }
    }

    // MARK: - GitHub Section

    private var githubSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GitHub Repo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("username/repo", text: $githubRepoInput)
                        .font(.caption.monospaced())
                        .autocorrectionDisabled()
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Personal Access Token")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("ghp_...", text: $githubPATInput)
                        .font(.caption.monospaced())
                        .autocorrectionDisabled()
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                }

                let githubChanged = githubRepoInput != appState.githubRepo || githubPATInput != appState.githubPAT
                Button("儲存 GitHub 設定") {
                    appState.githubRepo = githubRepoInput
                    appState.githubPAT = githubPATInput
                }
                .buttonStyle(.bordered)
                .font(.caption)
                .disabled(!githubChanged)
                .tint(githubChanged ? .accentColor : .secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("GitHub 設定（頻道管理）")
        } footer: {
            Text("需要有 repo 寫入權限的 PAT，用於在「頻道管理」頁面新增/刪除掃描頻道。")
        }
    }

    // MARK: - Extraction Mode Section

    private var extractionModeSection: some View {
        Section {
            Picker("全域偵測模式", selection: Binding(
                get: { sourcesConfig.globalExtractionMode ?? "keyword" },
                set: { newMode in
                    let mode: String? = newMode == "keyword" ? nil : newMode
                    Task { await saveGlobalExtractionMode(mode) }
                }
            )) {
                Text("僅關鍵字").tag("keyword")
                Text("關鍵字 + AI").tag("auto")
                Text("僅 AI").tag("gemini")
            }
        } header: {
            Text("股票偵測模式")
        } footer: {
            Text("「關鍵字 + AI」可偵測更多冷門股及修正 Whisper 錯字，但會消耗 Gemini API 額度。")
        }
        .disabled(!appState.hasGitHubConfig)
    }

    // MARK: - ETF Filter Section

    private var etfFilterSection: some View {
        @Bindable var appState = appState
        return Section {
            Toggle("台股指數 ETF（0050、006208）", isOn: $appState.showETFIndex)
            Toggle("高股息 ETF（0056、00878、00919…）", isOn: $appState.showETFDividend)
            Toggle("科技 ETF（00891…）", isOn: $appState.showETFTech)
            Toggle("主動型 ETF（00981A、00992A）", isOn: $appState.showETFActive)
            Toggle("債券 ETF（00679B、00720B…）", isOn: $appState.showETFBond)
            Toggle("槓桿反向 ETF（00631L、00632R）", isOn: $appState.showETFLeverage)
        } header: {
            Text("ETF 類別篩選")
        } footer: {
            Text("關閉後該類 ETF 不會出現在排行榜中")
        }
    }

    // MARK: - Data Info Section

    private var dataInfoSection: some View {
        Section {
            if let lastFetched = dataService.lastFetched {
                HStack {
                    Text("最後更新")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(lastFetched.formatted(.dateTime.month().day().hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            let result = dataService.scanResult
            HStack {
                Text("掃描影片/集數")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(result.videosScanned.count) 支")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("追蹤股票")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(result.stocksRanking.count) 支")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !result.updatedAt.isEmpty {
                HStack {
                    Text("資料更新時間")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(result.updatedDateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                Task { await dataService.fetchLatest(from: appState.dataURL) }
            } label: {
                if dataService.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("更新中…")
                    }
                } else {
                    Label("立即更新資料", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(dataService.isLoading || !appState.hasDataURL)
        } header: {
            Text("資料狀態")
        }
    }

    // MARK: - Danger Zone Section

    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showingClearAlert = true
            } label: {
                Label("清除本機快取", systemImage: "trash.fill")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .alert("確認清除快取", isPresented: $showingClearAlert) {
                Button("清除", role: .destructive) {
                    clearCache()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("將清除本機快取的掃描資料。重新整理後即可重新載入。")
            }
        } header: {
            Text("進階")
        }
    }

    private func clearCache() {
        dataService.clearCache()
    }
}
