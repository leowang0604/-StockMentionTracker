import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(DataService.self) private var dataService

    var body: some View {
        TabView {
            Tab("排行榜", systemImage: "chart.bar.fill") {
                RankingView()
            }
            Tab("族群", systemImage: "square.grid.2x2.fill") {
                SectorRankingView()
            }
            Tab("雷達", systemImage: "dot.radiowaves.left.and.right") {
                RadarView()
            }
            Tab("趨勢圖", systemImage: "chart.line.uptrend.xyaxis") {
                TrendView()
            }
            Tab("More", systemImage: "ellipsis") {
                MoreView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
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

private struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ContentListView(ownsNavigationStack: false)
                } label: {
                    Label("內容清單", systemImage: "list.bullet.rectangle")
                }

                NavigationLink {
                    ChannelManagementView()
                } label: {
                    Label("頻道管理", systemImage: "antenna.radiowaves.left.and.right")
                }

                NavigationLink {
                    SettingsView()
                } label: {
                    Label("設定", systemImage: "gear")
                }
            }
            .navigationTitle("More")
        }
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
