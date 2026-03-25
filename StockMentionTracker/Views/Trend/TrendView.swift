import SwiftUI
import Charts

struct TrendView: View {
    @Environment(AppState.self)    private var appState
    @Environment(DataService.self) private var dataService

    @State private var mode          = "stock"   // "stock" | "sector"
    @State private var selectedCode:   String? = nil
    @State private var selectedSector: String? = nil
    @State private var searchText              = ""

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

    private var selectedStock: StockEntry? {
        guard let code = selectedCode else { return nil }
        return dataService.scanResult.stocksRanking.first { $0.code == code }
    }

    private var stockChartData: [TrendDataPoint] {
        guard let stock = selectedStock else { return [] }
        let cutoff = appState.cutoffDate
        let filtered = stock.contexts.filter { ($0.parsedDate ?? .distantPast) >= cutoff }
        return grouped(from: filtered)
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
            let sector = String(k.dropFirst(3))   // remove "TW_" or "US_"
            return (sector, v.market, v.count)
        }
        .sorted { $0.count > $1.count }
        .filter { searchText.isEmpty || $0.sector.contains(searchText) }
    }

    private var sectorChartData: [TrendDataPoint] {
        guard let sector = selectedSector else { return [] }
        let cutoff = appState.cutoffDate
        let allContexts = dataService.scanResult.stocksRanking
            .filter { $0.sector == sector }
            .flatMap { $0.contexts }
            .filter { ($0.parsedDate ?? .distantPast) >= cutoff }
        return grouped(from: allContexts)
    }

    private var selectedSectorTotalMentions: Int {
        guard let sector = selectedSector else { return 0 }
        let cutoff = appState.cutoffDate
        return dataService.scanResult.stocksRanking
            .filter { $0.sector == sector }
            .flatMap { $0.contexts }
            .filter { ($0.parsedDate ?? .distantPast) >= cutoff }
            .count
    }

    // MARK: - Helpers

    private func grouped(from contexts: [MentionContext]) -> [TrendDataPoint] {
        let grouped = Dictionary(grouping: contexts) { ctx -> Date in
            let d = ctx.parsedDate ?? Date()
            return Calendar.current.startOfDay(for: d)
        }
        return grouped
            .map { TrendDataPoint(date: $0.key, count: $0.value.count) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Body

    var body: some View {
        @Bindable var appState = appState
        return NavigationStack {
            VStack(spacing: 0) {
                // Mode picker
                Picker("模式", selection: $mode) {
                    Text("個股").tag("stock")
                    Text("族群").tag("sector")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .onChange(of: mode) { _, _ in
                    selectedCode   = nil
                    selectedSector = nil
                    searchText     = ""
                }

                Divider()

                if mode == "stock" {
                    if let stock = selectedStock {
                        selectedStockHeader(stock: stock)
                        chartArea(data: stockChartData)
                        chartControls.padding()
                    } else {
                        stockSelector
                    }
                } else {
                    if let sector = selectedSector {
                        selectedSectorHeader(sector: sector)
                        chartArea(data: sectorChartData)
                        chartControls.padding()
                    } else {
                        sectorSelector
                    }
                }
            }
            .navigationTitle("趨勢圖")
            .searchable(text: $searchText,
                        prompt: mode == "stock" ? "搜尋股票" : "搜尋族群")
        }
    }

    // MARK: - Headers

    private func selectedStockHeader(stock: StockEntry) -> some View {
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
            Button("換股票") { selectedCode = nil; searchText = "" }
                .font(.subheadline).buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func selectedSectorHeader(sector: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(sector).font(.headline)
                Text("此區間提及 \(selectedSectorTotalMentions) 次")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("換族群") { selectedSector = nil; searchText = "" }
                .font(.subheadline).buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Chart

    @ViewBuilder
    private func chartArea(data: [TrendDataPoint]) -> some View {
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

    // MARK: - Chart controls

    private var chartControls: some View {
        @Bindable var appState = appState
        return HStack(spacing: 10) {
            Text("最近").font(.caption).foregroundStyle(.secondary)
            Slider(value: $appState.selectedDays, in: 1...90, step: 1)
            Text("\(Int(appState.selectedDays)) 天")
                .font(.caption.monospacedDigit())
                .frame(width: 44, alignment: .trailing)
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
                    Button {
                        selectedSector = item.sector
                        searchText     = ""
                    } label: {
                        HStack {
                            HStack(spacing: 6) {
                                if !item.market.isEmpty {
                                    Text(item.market)
                                        .font(.caption2)
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(.quaternary, in: Capsule())
                                        .foregroundStyle(.secondary)
                                }
                                Text(item.sector).font(.headline)
                            }
                            Spacer()
                            Text("\(item.count) 次")
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
            Text("選擇族群查看趨勢圖")
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }
}

struct TrendDataPoint: Identifiable {
    let id    = UUID()
    let date:  Date
    let count: Int
}
