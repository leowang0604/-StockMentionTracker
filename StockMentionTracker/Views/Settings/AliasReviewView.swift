import SwiftUI

struct AliasReviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var candidates: [String: AliasCandidate] = [:]
    @State private var isLoading = false
    @State private var processingID: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if !appState.hasGitHubConfig {
                    ContentUnavailableView {
                        Label("未設定 GitHub", systemImage: "gear")
                    } description: {
                        Text("請先在設定頁填入 GitHub Repo 和 Personal Access Token")
                    }
                } else if isLoading {
                    ProgressView("載入 Alias 候選…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if sortedCandidates.isEmpty {
                    VStack(spacing: 0) {
                        filterBar
                        ContentUnavailableView {
                            Label("沒有待審核候選", systemImage: "checkmark.circle")
                        } description: {
                            Text("目前時間範圍內沒有待審核候選。")
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        filterBar
                        List(sortedCandidates) { candidate in
                            candidateRow(candidate)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .refreshable { await loadCandidates() }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
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

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")

            Text("Alias 候選審核")
                .font(.title.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()

            Button {
                Task { await loadCandidates() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .accessibilityLabel("重新整理")
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.black)
    }

    private var sortedCandidates: [AliasCandidate] {
        candidates.values
            .filter { !filteredEvidence(for: $0).isEmpty }
            .sorted { lhs, rhs in
                let lhsEvidence = filteredEvidence(for: lhs)
                let rhsEvidence = filteredEvidence(for: rhs)
                let lhsScore = lhsEvidence.map(\.score).max() ?? lhs.maxScore
                let rhsScore = rhsEvidence.map(\.score).max() ?? rhs.maxScore
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                return lhsEvidence.count > rhsEvidence.count
        }
    }

    private var filterBar: some View {
        @Bindable var appState = appState
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("最近")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $appState.selectedDays, in: 1...60, step: 1)
                Text("\(Int(appState.selectedDays)) 天")
                    .font(.caption.monospacedDigit())
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            Divider()
        }
        .background(Color.black)
    }

    private func candidateRow(_ candidate: AliasCandidate) -> some View {
        let evidenceInRange = filteredEvidence(for: candidate)
        let latestEvidence = evidenceInRange.last
        let videoCount = Set(evidenceInRange.map(\.videoID).filter { !$0.isEmpty }).count
        let displayScore = evidenceInRange.map(\.score).max() ?? candidate.maxScore
        return VStack(alignment: .leading, spacing: 10) {
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
                Text("\(displayScore)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text("\(videoCount) 支影片 · \(evidenceInRange.count) 次觀察")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let phoneticCandidates = candidate.phoneticCandidates, !phoneticCandidates.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("發音接近")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(phoneticCandidates.map {
                        "\($0.name) \($0.code) \(Int($0.score * 100))%"
                    }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let evidence = latestEvidence {
                sourceLine(for: evidence)
                if let overrideSummary = overrideSummary(for: candidate, evidence: evidence) {
                    Text(overrideSummary)
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                Text(highlightedMentionText(evidence.context, terms: aliasHighlightTerms(for: candidate)))
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
        .listRowBackground(Color.black)
    }

    @ViewBuilder
    private func sourceLine(for evidence: AliasEvidence) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: evidence.youtubeURL == nil ? "waveform" : "play.rectangle.fill")
                    .foregroundStyle(sourceIconColor(for: evidence))
                Text([evidence.channel, evidence.dateText].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let url = evidence.youtubeURL {
                    Link(destination: url) {
                        Label("開啟", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                }
            }
            if !evidence.title.isEmpty {
                Text(evidence.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func sourceIconColor(for evidence: AliasEvidence) -> Color {
        evidence.youtubeURL == nil ? .secondary : .red
    }

    private func filteredEvidence(for candidate: AliasCandidate) -> [AliasEvidence] {
        let cutoff = appState.cutoffDate
        return candidate.evidence.filter { ($0.parsedDate ?? .distantPast) >= cutoff }
    }

    private func aliasHighlightTerms(for candidate: AliasCandidate) -> [String] {
        var terms = [
            candidate.wrongKeyword,
            candidate.correctName,
            candidate.correctCode,
        ]
        if let phoneticCandidates = candidate.phoneticCandidates {
            for phoneticCandidate in phoneticCandidates.prefix(3) {
                terms.append(phoneticCandidate.name)
                terms.append(phoneticCandidate.code)
            }
        }
        return Array(Set(terms))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.count > $1.count }
    }

    private func overrideSummary(for candidate: AliasCandidate, evidence: AliasEvidence) -> String? {
        guard let kind = evidence.overrideKind, !kind.isEmpty else { return nil }
        let label: String
        switch kind {
        case "phonetic":
            label = "音近反轉"
        case "contextual":
            label = "語境修正"
        default:
            label = kind
        }

        var pieces = [label]
        if let originalName = evidence.originalName, let originalCode = evidence.originalCode,
           !originalName.isEmpty, !originalCode.isEmpty {
            pieces.append("原本：\(originalName) \(originalCode)")
        }
        pieces.append("改用：\(candidate.correctName) \(candidate.correctCode)")

        if let score = evidence.phoneticTopScore {
            var scoreText = "音近 \(Int((score * 100).rounded()))%"
            if let lead = evidence.phoneticLead {
                scoreText += "，領先 \(Int((lead * 100).rounded()))%"
            }
            pieces.append(scoreText)
        } else if let reason = evidence.overrideReason, !reason.isEmpty {
            pieces.append(reason)
        }
        return pieces.joined(separator: " · ")
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
