import SwiftUI
import Charts

struct TrendView: View {
    @Environment(AppState.self)    private var appState
    @Environment(DataService.self) private var dataService

    @State private var selectedCode: String? = nil
    @State private var searchText            = ""

    // Stocks filtered by current date range
    private var rankedStocks: [(code: String, name: String, count: Int)] {
        let cutoff = appState.cutoffDate
        return dataService.scanResult.stocksRanking
            .compactMap { stock -> (String, String, Int)? in
                let n = stock.contexts.filter { ($0.parsedDate ?? .distantPast) >= cutoff }.count
                guard n > 0 else { return nil }
                return (stock.code, stock.name, n)
            }
            .sorted { $0.2 > $1.2 }
            .filter {
                searchText.isEmpty || $0.1.contains(searchText) || $0.0.contains(searchText)
            }
    }

    private var selectedStock: StockEntry? {
        guard let code = selectedCode else { return nil }
        return dataService.scanResult.stocksRanking.first { $0.code == code }
    }

    // Chart data: group filtered contexts by date
    private var chartData: [TrendDataPoint] {
        guard let stock = selectedStock else { return [] }
        let cutoff = appState.cutoffDate
        let filtered = stock.contexts.filter { ($0.parsedDate ?? .distantPast) >= cutoff }
        let grouped  = Dictionary(grouping: filtered) { ctx -> Date in
            let d = ctx.parsedDate ?? Date()
            return Calendar.current.startOfDay(for: d)
        }
        return grouped
            .map { TrendDataPoint(date: $0.key, count: $0.value.count) }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        @Bindable var appState = appState
        return NavigationStack {
            VStack(spacing: 0) {
                if let stock = selectedStock {
                    selectedHeader(stock: stock)
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

    // MARK: - Selected stock header

    private func selectedHeader(stock: StockEntry) -> some View {
        @Bindable var appState = appState
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(stock.name).font(.headline)
                    Text(stock.code).font(.caption).foregroundStyle(.secondary)
                }
                let filtered = stock.contexts.filter {
                    ($0.parsedDate ?? .distantPast) >= appState.cutoffDate
                }
                Text("此區間提及 \(filtered.count) 次")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("換股票") {
                selectedCode = nil
                searchText   = ""
            }
            .font(.subheadline)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Chart

    @ViewBuilder
    private var chartArea: some View {
        let data = chartData
        let days = Int(appState.selectedDays)
        if data.isEmpty {
            ContentUnavailableView(
                "此時間範圍無資料",
                systemImage: "chart.line.flattrend.xyaxis",
                description: Text("請選擇更長的時間範圍或換一支股票")
            )
            .frame(height: 250)
        } else {
            Chart(data) { point in
                LineMark(x: .value("日期", point.date), y: .value("次數", point.count))
                    .foregroundStyle(Color.accentColor)
                    .symbol(Circle())
                AreaMark(x: .value("日期", point.date), y: .value("次數", point.count))
                    .foregroundStyle(Color.accentColor.opacity(0.15))
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

    // MARK: - Chart controls (slider)

    private var chartControls: some View {
        @Bindable var appState = appState
        return HStack(spacing: 10) {
            Text("最近")
                .font(.caption).foregroundStyle(.secondary)
            Slider(value: $appState.selectedDays, in: 7...90, step: 1)
            Text("\(Int(appState.selectedDays)) 天")
                .font(.caption.monospacedDigit())
                .frame(width: 44, alignment: .trailing)
        }
    }

    // MARK: - Stock selector list

    private var stockSelector: some View {
        List {
            if rankedStocks.isEmpty {
                Text("尚無股票資料")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(rankedStocks, id: \.code) { stock in
                    Button {
                        selectedCode = stock.code
                        searchText   = ""
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
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .listStyle(.plain)
        .overlay(alignment: .top) {
            Text("選擇股票查看趨勢圖")
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }
}

struct TrendDataPoint: Identifiable {
    let id   = UUID()
    let date: Date
    let count: Int
}
