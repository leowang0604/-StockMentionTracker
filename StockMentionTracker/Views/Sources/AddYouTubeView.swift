import SwiftUI

// MARK: - Add Channel View

struct AddChannelView: View {
    let onAdd: (ChannelSource) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var channelID = ""
    @State private var sourceType: SourceType = .youtube

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !channelID.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("類型", selection: $sourceType) {
                        ForEach(SourceType.allCases, id: \.self) {
                            Label($0.displayName, systemImage: $0.icon).tag($0)
                        }
                    }
                } header: {
                    Text("來源類型")
                }

                Section {
                    TextField("名稱（例：Yahoo Finance）", text: $name)
                        .autocorrectionDisabled()
                } header: {
                    Text("頻道名稱")
                }

                Section {
                    TextField(channelIDPlaceholder, text: $channelID)
                        .autocorrectionDisabled()
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
#endif
                        .onChange(of: channelID) { _, raw in
                            if let parsed = parseIdentifier(from: raw, type: sourceType) {
                                channelID = parsed
                            }
                        }
                } header: {
                    Text(channelIDLabel)
                } footer: {
                    Text(channelIDFooter)
                }
            }
            .navigationTitle("新增頻道")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("新增") {
                        let channel = ChannelSource(
                            id: UUID().uuidString,
                            name: name.trimmingCharacters(in: .whitespaces),
                            type: sourceType.rawValue,
                            identifier: channelID.trimmingCharacters(in: .whitespaces),
                            active: true
                        )
                        onAdd(channel)
                        dismiss()
                    }
                    .disabled(!canAdd)
                }
            }
        }
    }

    private var channelIDLabel: String {
        switch sourceType {
        case .youtube: return "YouTube 頻道 ID"
        case .applePodcast: return "Apple Podcast ID"
        case .spotify: return "Spotify Show ID"
        }
    }

    private var channelIDPlaceholder: String {
        switch sourceType {
        case .youtube: return "UCxxxxxxxxxxxxxxxxxxxxxxx"
        case .applePodcast: return "1234567890"
        case .spotify: return "xxxxxxxxxxxxxxxxxxxxxxxx"
        }
    }

    // Auto-parse ID from URL
    private func parseIdentifier(from input: String, type: SourceType) -> String? {
        guard input.contains("http") else { return nil }
        switch type {
        case .applePodcast:
            // https://podcasts.apple.com/.../id1590806478
            if let range = input.range(of: #"/id(\d+)"#, options: .regularExpression) {
                let match = String(input[range])
                return String(match.dropFirst(3)) // drop "/id"
            }
        case .youtube:
            // https://www.youtube.com/channel/UCxxxxxx or /c/name or /@handle
            if let range = input.range(of: #"youtube\.com/channel/(UC[^/?&]+)"#, options: .regularExpression) {
                let match = String(input[range])
                if let idRange = match.range(of: "UC[^/?&]+", options: .regularExpression) {
                    return String(match[idRange])
                }
            }
        case .spotify:
            // https://open.spotify.com/show/xxxxxxxx
            if let range = input.range(of: #"spotify\.com/show/([^/?&]+)"#, options: .regularExpression) {
                let match = String(input[range])
                if let idRange = match.range(of: "[^/]+$", options: .regularExpression) {
                    return String(match[idRange])
                }
            }
        }
        return nil
    }

    private var channelIDFooter: String {
        switch sourceType {
        case .youtube:
            return "可直接貼上頻道連結，自動提取 UC 開頭的 ID。"
        case .applePodcast:
            return "可直接貼上 Apple Podcast 連結，自動提取數字 ID。"
        case .spotify:
            return "可直接貼上 Spotify 節目連結，自動提取 Show ID。"
        }
    }
}
