import SwiftUI

struct AliasReviewView: View {
    @Environment(AppState.self) private var appState

    @State private var candidates: [String: AliasCandidate] = [:]
    @State private var isLoading = false
    @State private var processingID: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if !appState.hasGitHubConfig {
                ContentUnavailableView {
                    Label("未設定 GitHub", systemImage: "gear")
                } description: {
                    Text("請先在設定頁填入 GitHub Repo 和 Personal Access Token")
                }
            } else if isLoading {
                ProgressView("載入 Alias 候選…")
            } else if sortedCandidates.isEmpty {
                ContentUnavailableView {
                    Label("沒有待審核候選", systemImage: "checkmark.circle")
                } description: {
                    Text("每日掃描發現新的 Whisper 錯字後，會顯示在這裡。")
                }
            } else {
                List(sortedCandidates) { candidate in
                    candidateRow(candidate)
                }
                .refreshable { await loadCandidates() }
            }
        }
        .navigationTitle("Alias 候選審核")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await loadCandidates() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .disabled(isLoading)
            }
        }
        .task { await loadCandidates() }
        .alert("發生錯誤", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("確定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var sortedCandidates: [AliasCandidate] {
        candidates.values.sorted {
            if $0.maxScore != $1.maxScore { return $0.maxScore > $1.maxScore }
            return $0.observations > $1.observations
        }
    }

    private func candidateRow(_ candidate: AliasCandidate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(candidate.wrongKeyword)
                    .font(.headline)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Text(candidate.correctName)
                    .font(.headline)
                Text(candidate.correctCode)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(candidate.maxScore)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text("\(candidate.distinctVideos) 支影片 · \(candidate.observations) 次觀察")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let evidence = candidate.evidence.last {
                if !evidence.title.isEmpty {
                    Text(evidence.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(evidence.context)
                    .font(.caption)
                    .lineLimit(5)
            }

            HStack {
                Button {
                    Task { await accept(candidate) }
                } label: {
                    Label("接受", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button(role: .destructive) {
                    Task { await reject(candidate) }
                } label: {
                    Label("拒絕", systemImage: "xmark")
                }
                .buttonStyle(.bordered)

                if processingID == candidate.id {
                    ProgressView()
                        .padding(.leading, 4)
                }
            }
            .disabled(processingID != nil)
        }
        .padding(.vertical, 6)
    }

    private func loadCandidates() async {
        guard appState.hasGitHubConfig else { return }
        isLoading = true
        do {
            let file = try await GitHubService.shared.fetchJSON(
                [String: AliasCandidate].self,
                repo: appState.githubRepo,
                pat: appState.githubPAT,
                path: "data/alias_candidates.json",
                defaultValue: [:]
            )
            candidates = file.value
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func accept(_ candidate: AliasCandidate) async {
        await process(candidate, accepted: true)
    }

    private func reject(_ candidate: AliasCandidate) async {
        await process(candidate, accepted: false)
    }

    private func process(_ candidate: AliasCandidate, accepted: Bool) async {
        guard processingID == nil else { return }
        processingID = candidate.id
        do {
            if accepted {
                try await updateLearnedAliases(candidate)
            } else {
                try await updateRejectedAliases(candidate)
            }
            try await removeCandidate(candidate)
            candidates.removeValue(forKey: candidate.id)
        } catch {
            errorMessage = error.localizedDescription
            await loadCandidates()
        }
        processingID = nil
    }

    private func updateLearnedAliases(_ candidate: AliasCandidate) async throws {
        let file = try await GitHubService.shared.fetchJSON(
            [String: String].self,
            repo: appState.githubRepo,
            pat: appState.githubPAT,
            path: "data/learned_aliases.json",
            defaultValue: [:]
        )
        var aliases = file.value
        aliases[candidate.wrongKeyword] = candidate.correctCode
        try await GitHubService.shared.saveJSON(
            aliases,
            repo: appState.githubRepo,
            pat: appState.githubPAT,
            path: "data/learned_aliases.json",
            sha: file.sha,
            message: "Accept alias \(candidate.wrongKeyword) -> \(candidate.correctCode)"
        )
    }

    private func updateRejectedAliases(_ candidate: AliasCandidate) async throws {
        let file = try await GitHubService.shared.fetchJSON(
            [String: RejectedAlias].self,
            repo: appState.githubRepo,
            pat: appState.githubPAT,
            path: "data/rejected_aliases.json",
            defaultValue: [:]
        )
        var aliases = file.value
        aliases[candidate.id] = RejectedAlias(
            wrongKeyword: candidate.wrongKeyword,
            correctCode: candidate.correctCode,
            correctName: candidate.correctName,
            rejectedAt: ISO8601DateFormatter().string(from: Date())
        )
        try await GitHubService.shared.saveJSON(
            aliases,
            repo: appState.githubRepo,
            pat: appState.githubPAT,
            path: "data/rejected_aliases.json",
            sha: file.sha,
            message: "Reject alias \(candidate.wrongKeyword) -> \(candidate.correctCode)"
        )
    }

    private func removeCandidate(_ candidate: AliasCandidate) async throws {
        let file = try await GitHubService.shared.fetchJSON(
            [String: AliasCandidate].self,
            repo: appState.githubRepo,
            pat: appState.githubPAT,
            path: "data/alias_candidates.json",
            defaultValue: [:]
        )
        var latestCandidates = file.value
        latestCandidates.removeValue(forKey: candidate.id)
        try await GitHubService.shared.saveJSON(
            latestCandidates,
            repo: appState.githubRepo,
            pat: appState.githubPAT,
            path: "data/alias_candidates.json",
            sha: file.sha,
            message: "Review alias \(candidate.wrongKeyword) -> \(candidate.correctCode)"
        )
    }
}
