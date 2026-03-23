import SwiftUI
import Charts

struct TrendView: View {
    @Environment(AppState.self) private var appState
    @Environment(DataService.self) private var dataService

    @State private var selectedStock: String? = nil
    @State private var sourceFilter: TrendSourceFilter = .all
    @State private var searchText = ""

    enum TrendSourceFilter: String, CaseIterable {
        case all = "全部"
        case youtube = "YouTube"
        case podcast = "Podcast"

        var color: Color {
            switch self {
            case .all: return .blue
            case .youtube: return .red
            case .podcast: return .purple
            }
        }
    }

    private var allMentions: [MentionInfo] { dataService.scanResult.mentions }

    private var filteredMentions: [MentionInfo] {
        allMentions.filter { $0.mentionedDate >= appState.cutoffDate }
    }

    private var allStocks: [(code: String, name: String, count: Int)] {
        let grouped = Dictionary(grouping: filteredMentions) { $0.stockCode }
        return grouped.compactMap { (code, mentions) -> (String, String, Int)? in
            guard let first = mentions.first else { return nil }
            return (code, first.stockName, mentions.count)
        }
        .sorted { $0.2 > $1.2 }
        .filter {
            searchText.isEmpty || $0.1.contains(searchText) || $0.0.contains(searchText)
        }
    }

    private func chartData(for filter: TrendSourceFilter) -> [TrendDataPoint] {
        guard let code = selectedStock else { return [] }
        let mentions = filteredMentions.filter { mention in
            mention.stockCode == code &&
            filterMatches(mention, filter: filter)
        }
        let grouped = Dictionary(grouping: mentions) { Calendar.current.startOfDay(for: $0.mentionedDate) }
        return grouped.map { TrendDataPoint(date: $0.key, count: $0.value.count) }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let code = selectedStock,
                   let stockInfo = allStocks.first(where: { $0.code == code }) {
                    selectedStockHeader(stockInfo: stockInfo)
                    chartArea
                    chartControls.padding()
                } else {
                    stockSelector
                }
            }
            .navigationTitle("趨勢圖")
            .searchable(text: $searchText, prompt: "搜尋股票")
        }
    }

    private func selectedStockHeader(stockInfo: (code: String, name: String, count: Int)) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(stockInfo.name).font(.headline)
                    Text(stockInfo.code).font(.caption).foregroundStyle(.secondary)
                }
                Text("總提及 \(stockInfo.count) 次").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("換股票") {
                selectedStock = nil
                searchText = ""
            }
            .font(.subheadline)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var chartArea: some View {
        @Bindable var appState = appState
        let data = chartData(for: sourceFilter)
        let days = Int(appState.selectedDays)
        if data.isEmpty {
            ContentUnavailableView(
                "此時間範圍無資料",
                systemImage: "chart.line.flattrend.xyaxis",
                description: Text("請選擇更長的時間範圍")
            )
            .frame(height: 250)
        } else {
            Chart(data) { point in
                LineMark(x: .value("日期", point.date), y: .value("次數", point.count))
                    .foregroundStyle(sourceFilter.color)
                    .symbol(Circle())
                AreaMark(x: .value("日期", point.date), y: .value("次數", point.count))
                    .foregroundStyle(sourceFilter.color.opacity(0.15))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: days > 30 ? 14 : 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .frame(height: 250)
            .padding()
        }
    }

    private var chartControls: some View {
        @Bindable var appState = appState
        return VStack(spacing: 12) {
            Picker("來源", selection: $sourceFilter) {
                ForEach(TrendSourceFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

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
        }
    }

    private var stockSelector: some View {
        List {
            if allStocks.isEmpty {
                Text("尚無股票資料")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(allStocks, id: \.code) { stock in
                    Button {
                        selectedStock = stock.code
                        searchText = ""
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(stock.name).font(.headline)
                                    Text(stock.code).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("\(stock.count) 次")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .listStyle(.plain)
        .overlay(alignment: .top) {
            Text("選擇股票查看趨勢圖")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    private func filterMatches(_ mention: MentionInfo, filter: TrendSourceFilter) -> Bool {
        switch filter {
        case .all: return true
        case .youtube: return mention.sourceType == SourceType.youtube.rawValue
        case .podcast:
            return mention.sourceType == SourceType.applePodcast.rawValue ||
                   mention.sourceType == SourceType.spotify.rawValue
        }
    }
}

struct TrendDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
}
