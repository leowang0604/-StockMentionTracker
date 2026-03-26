import SwiftUI
import Charts

struct TrendView: View {
    @Environment(AppState.self)    private var appState
    @Environment(DataService.self) private var dataService

    @State private var mode      = "stock"   // "stock" | "sector"
    @State private var searchText = ""

    // MARK: - Stock mode data

    private var rankedStocks: [(code: String, name: String, count: Int)] {
        let cutoff = appState.cutoffDate
        return dataService.scanResult.stocksRanking
            .compactMap { stock -> (String, String, Int)? in
                let n = stock.contexts.filter { ($0.parsedDate ?? .distantPast) >= cutoff }.count
                guard n > 0 else { return nil }
                return (stock.code, stock.name, n)
            }
            .sorted { $0.2 > $1.2 }
            .filter { searchText.isEmpty || $0.1.contains(searchText) || $0.0.contains(searchText) }
    }

    // MARK: - Sector mode data

    private var rankedSectors: [(sector: String, market: String, count: Int)] {
        let cutoff = appState.cutoffDate
        var map: [String: (market: String, count: Int)] = [:]
        for stock in dataService.scanResult.stocksRanking {
            guard let sector = stock.sector else { continue }
            let n = stock.contexts.filter { ($0.parsedDate ?? .distantPast) >= cutoff }.count
            guard n > 0 else { continue }
            let key = "\(stock.market ?? "TW")_\(sector)"
            let existing = map[key] ?? (stock.market ?? "TW", 0)
            map[key] = (existing.market, existing.count + n)
        }
        return map.map { (k, v) in
            let sector = String(k.dropFirst(3))
            return (sector, v.market, v.count)
        }
        .sorted { $0.count > $1.count }
        .filter { searchText.isEmpty || $0.sector.contains(searchText) }
    }

    // MARK: - Body

    var body: some View {
        @Bindable var appState = appState
        return NavigationStack {
            VStack(spacing: 0) {
                Picker("模式", selection: $mode) {
                    Text("個股").tag("stock")
                    Text("族群").tag("sector")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .onChange(of: mode) { _, _ in searchText = "" }

                HStack(spacing: 10) {
                    Text("最近").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $appState.selectedDays, in: 1...90, step: 1)
                    Text("\(Int(appState.selectedDays)) 天")
                        .font(.caption.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                Divider()

                if mode == "stock" {
                    stockSelector
                } else {
                    sectorSelector
                }
            }
            .navigationTitle("趨勢圖")
            .searchable(text: $searchText,
                        prompt: mode == "stock" ? "搜尋股票" : "搜尋族群")
        }
    }

    // MARK: - Stock selector

    private var stockSelector: some View {
        List {
            if rankedStocks.isEmpty {
                Text("尚無股票資料")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(rankedStocks, id: \.code) { stock in
                    NavigationLink(destination: StockTrendDetailView(stockCode: stock.code)) {
                        HStack {
                            Text(stock.name).font(.headline)
                            Text(stock.code).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(stock.count) 次")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Sector selector

    private var sectorSelector: some View {
        List {
            if rankedSectors.isEmpty {
                Text("尚無族群資料")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(rankedSectors, id: \.sector) { item in
                    NavigationLink(destination: SectorTrendDetailView(sector: item.sector)) {
                        HStack {
                            if !item.market.isEmpty {
                                Text(item.market)
                                    .font(.caption2)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                                    .foregroundStyle(.secondary)
                            }
                            Text(item.sector).font(.headline)
                            Spacer()
                            Text("\(item.count) 次")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Stock Trend Detail

struct StockTrendDetailView: View {
    @Environment(AppState.self)    private var appState
    @Environment(DataService.self) private var dataService

    let stockCode: String
    @State private var chartMode = "mentions"

    private var stock: StockEntry? {
        dataService.scanResult.stocksRanking.first { $0.code == stockCode }
    }

    private var chartData: [TrendDataPoint] {
        guard let stock else { return [] }
        let cutoff = appState.cutoffDate
        let filtered = stock.contexts.filter { ($0.parsedDate ?? .distantPast) >= cutoff }
        return grouped(from: filtered)
    }

    private var sentimentData: [SentimentDataPoint] {
        guard let daily = stock?.daily else { return [] }
        let cutoff = appState.cutoffDate
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        return daily.compactMap { (dateStr, stats) -> SentimentDataPoint? in
            guard let date = fmt.date(from: dateStr),
                  Calendar.current.startOfDay(for: date) >= Calendar.current.startOfDay(for: cutoff),
                  stats.bullish + stats.bearish > 0
            else { return nil }
            return SentimentDataPoint(date: date, score: stats.sentimentScore,
                                      bullish: stats.bullish, bearish: stats.bearish)
        }.sorted { $0.date < $1.date }
    }

    var body: some View {
        @Bindable var appState = appState
        guard let stock else { return AnyView(Text("找不到股票")) }
        let cutoff = appState.cutoffDate
        let mentions = stock.contexts.filter { ($0.parsedDate ?? .distantPast) >= cutoff }.count

        return AnyView(
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("最近").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $appState.selectedDays, in: 1...90, step: 1)
                    Text("\(Int(appState.selectedDays)) 天")
                        .font(.caption.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                HStack {
                    Text("此區間提及 \(mentions) 次")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 4)

                Picker("圖表", selection: $chartMode) {
                    Text("提及次數").tag("mentions")
                    Text("情緒趨勢").tag("sentiment")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 4)

                Divider()

                if chartMode == "mentions" {
                    mentionsChart
                } else {
                    sentimentChart
                }

                Spacer()
            }
            .navigationTitle("\(stock.name)  \(stock.code)")
            .navigationBarTitleDisplayMode(.inline)
        )
    }

    private var mentionsChart: some View {
        let days = Int(appState.selectedDays)
        return Group {
            if chartData.isEmpty {
                ContentUnavailableView("此時間範圍無資料",
                    systemImage: "chart.line.flattrend.xyaxis",
                    description: Text("請選擇更長的時間範圍"))
                .frame(height: 250)
            } else {
                let maxCount = chartData.map(\.count).max() ?? 1
                Chart(chartData) { point in
                    LineMark(x: .value("日期", point.date), y: .value("次數", point.count))
                        .foregroundStyle(Color.accentColor)
                        .symbol(Circle())
                    AreaMark(x: .value("日期", point.date), y: .value("次數", point.count))
                        .foregroundStyle(LinearGradient(
                            colors: [Color.accentColor.opacity(0.5), Color.accentColor.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom))
                }
                .chartYScale(domain: 0...(maxCount + 1))
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
    }

    private var sentimentChart: some View {
        let days = Int(appState.selectedDays)
        return Group {
            if sentimentData.count < 3 {
                ContentUnavailableView("資料點不足",
                    systemImage: "chart.line.flattrend.xyaxis",
                    description: Text("需要至少 3 天以上的情緒資料才能顯示趨勢，請等待更多掃描累積"))
                .frame(height: 250)
            } else {
                Chart(sentimentData) { point in
                    BarMark(x: .value("日期", point.date, unit: .day),
                            y: .value("看多", point.bullish),
                            stacking: .unstacked)
                        .foregroundStyle(.green.opacity(0.7))
                    BarMark(x: .value("日期", point.date, unit: .day),
                            y: .value("看空", point.bearish),
                            stacking: .unstacked)
                        .foregroundStyle(.red.opacity(0.5))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: days > 30 ? 14 : 7)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartForegroundStyleScale(["看多": Color.green.opacity(0.7), "看空": Color.red.opacity(0.5)])
                .frame(height: 250)
                .padding()
            }
        }
    }

    private func grouped(from contexts: [MentionContext]) -> [TrendDataPoint] {
        let grouped = Dictionary(grouping: contexts) { ctx -> Date in
            let d = ctx.parsedDate ?? Date()
            return Calendar.current.startOfDay(for: d)
        }
        return grouped
            .map { TrendDataPoint(date: $0.key, count: $0.value.count) }
            .sorted { $0.date < $1.date }
    }
}

// MARK: - Sector Trend Detail

struct SectorTrendDetailView: View {
    @Environment(AppState.self)    private var appState
    @Environment(DataService.self) private var dataService

    let sector: String

    private var chartData: [TrendDataPoint] {
        let cutoff = appState.cutoffDate
        let allContexts = dataService.scanResult.stocksRanking
            .filter { $0.sector == sector }
            .flatMap { $0.contexts }
            .filter { ($0.parsedDate ?? .distantPast) >= cutoff }
        let grouped = Dictionary(grouping: allContexts) { ctx -> Date in
            Calendar.current.startOfDay(for: ctx.parsedDate ?? Date())
        }
        return grouped
            .map { TrendDataPoint(date: $0.key, count: $0.value.count) }
            .sorted { $0.date < $1.date }
    }

    private var totalMentions: Int {
        let cutoff = appState.cutoffDate
        return dataService.scanResult.stocksRanking
            .filter { $0.sector == sector }
            .flatMap { $0.contexts }
            .filter { ($0.parsedDate ?? .distantPast) >= cutoff }
            .count
    }

    var body: some View {
        @Bindable var appState = appState
        let days = Int(appState.selectedDays)

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("最近").font(.caption).foregroundStyle(.secondary)
                Slider(value: $appState.selectedDays, in: 1...90, step: 1)
                Text("\(Int(appState.selectedDays)) 天")
                    .font(.caption.monospacedDigit())
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            HStack {
                Text("此區間提及 \(totalMentions) 次")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 4)

            Divider()

            if chartData.isEmpty {
                ContentUnavailableView("此時間範圍無資料",
                    systemImage: "chart.line.flattrend.xyaxis",
                    description: Text("請選擇更長的時間範圍"))
                .frame(height: 250)
            } else {
                Chart(chartData) { point in
                    LineMark(x: .value("日期", point.date), y: .value("次數", point.count))
                        .foregroundStyle(Color.accentColor)
                        .symbol(Circle())
                    AreaMark(x: .value("日期", point.date), y: .value("次數", point.count))
                        .foregroundStyle(LinearGradient(
                            colors: [Color.accentColor.opacity(0.5), Color.accentColor.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom))
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

            Spacer()
        }
        .navigationTitle(sector)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Data Models

struct TrendDataPoint: Identifiable {
    let id    = UUID()
    let date:  Date
    let count: Int
}

struct SentimentDataPoint: Identifiable {
    let id      = UUID()
    let date:    Date
    let score:   Double
    let bullish: Int
    let bearish: Int
}
