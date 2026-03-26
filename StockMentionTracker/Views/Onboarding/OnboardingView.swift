import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(DataService.self) private var dataService

    @State private var dataURLInput = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Icon + Title
                VStack(spacing: 16) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.accentColor)

                    Text("Stock Mention Tracker")
                        .font(.largeTitle.bold())

                    Text("追蹤 YouTube 財經頻道與 Podcast 中的台股與美股提及")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                // Setup Form
                VStack(alignment: .leading, spacing: 12) {
                    Text("GitHub Raw URL")
                        .font(.headline)

                    TextField(
                        "https://raw.githubusercontent.com/user/repo/main/data/latest.json",
                        text: $dataURLInput
                    )
                    .font(.caption.monospaced())
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    .autocorrectionDisabled()
#if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
#endif

                    Text("建立 GitHub 公開 repo 並設定 GitHub Actions 每日掃描後，貼入 data/latest.json 的 Raw URL。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal)

                // Continue Button
                Button {
                    Task { await setup() }
                } label: {
                    Group {
                        if isLoading {
                            ProgressView().scaleEffect(0.9)
                        } else {
                            Text("開始使用")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canProceed ? Color.accentColor : Color.accentColor.opacity(0.4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canProceed || isLoading)
                .padding(.horizontal)

                Button("稍後設定，先試用") {
                    appState.hasCompletedOnboarding = true
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Spacer()
            }
            .navigationTitle("")
        }
    }

    private var canProceed: Bool {
        !dataURLInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func setup() async {
        let url = dataURLInput.trimmingCharacters(in: .whitespaces)
        appState.dataURL = url
        isLoading = true
        errorMessage = nil
        await dataService.fetchLatest(from: url)
        isLoading = false
        if dataService.errorMessage != nil {
            errorMessage = "無法從該 URL 載入資料，請確認格式是否正確。"
        } else {
            appState.hasCompletedOnboarding = true
        }
    }
}
