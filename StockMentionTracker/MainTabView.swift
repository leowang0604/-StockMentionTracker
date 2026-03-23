import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(DataService.self) private var dataService

    var body: some View {
        TabView {
            RankingView()
                .tabItem {
                    Label("排行榜", systemImage: "chart.bar.fill")
                }

            TrendView()
                .tabItem {
                    Label("趨勢圖", systemImage: "chart.line.uptrend.xyaxis")
                }

            ContentListView()
                .tabItem {
                    Label("內容清單", systemImage: "list.bullet.rectangle")
                }

            ChannelManagementView()
                .tabItem {
                    Label("頻道管理", systemImage: "antenna.radiowaves.left.and.right")
                }

            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gear")
                }
        }
        .overlay(alignment: .bottom) {
            if dataService.isLoading {
                LoadingBanner()
                    .padding(.bottom, 60)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: dataService.isLoading)
    }
}

// MARK: - Loading Banner

struct LoadingBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.8)
            Text("更新資料中…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .shadow(radius: 4)
    }
}
