import Charts
import SwiftUI

struct HistoryView: View {
    let drinkLog: DrinkLogStore
    let unit: SettingsStore.VolumeUnit

    @State private var range = HistoryRange.week
    @State private var selectedKinds = Set(DrinkKind.allCases)
    @State private var chartPoints: [DailyDrinkTotal] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HistoryRangePicker(range: $range)
                DrinkTypeFilters(
                    selectedKinds: $selectedKinds
                )

                HistoryChart(
                    points: chartPoints,
                    range: range,
                    unitLabel: unit.label
                )

                HistoryTotals(
                    points: chartPoints,
                    selectedKinds: selectedKinds,
                    unit: unit
                )
            }
            .padding()
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            updateChartPoints()
        }
        .onChange(of: range) {
            updateChartPoints()
        }
        .onChange(of: selectedKinds) {
            updateChartPoints()
        }
        .onChange(of: unit) {
            updateChartPoints()
        }
        .onChange(of: drinkLog.events) {
            updateChartPoints()
        }
    }

    private func updateChartPoints() {
        chartPoints = drinkLog.dailyTotals(
            days: range.dayCount,
            kinds: selectedKinds,
            unit: unit
        )
    }
}

private struct HistoryRangePicker: View {
    @Binding var range: HistoryRange

    var body: some View {
        Picker("Date Range", selection: $range) {
            ForEach(HistoryRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
    }
}

private struct DrinkTypeFilters: View {
    @Binding var selectedKinds: Set<DrinkKind>

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(DrinkKind.allCases) { kind in
                    Button {
                        toggle(kind)
                    } label: {
                        Label(kind.title, systemImage: kind.symbol)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(selectedKinds.contains(kind) ? kind.color : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selectedKinds.contains(kind)
                                    ? kind.color.opacity(0.15)
                                    : Color.secondary.opacity(0.08),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedKinds.contains(kind) ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func toggle(_ kind: DrinkKind) {
        if selectedKinds.contains(kind) {
            guard selectedKinds.count > 1 else { return }
            selectedKinds.remove(kind)
        } else {
            selectedKinds.insert(kind)
        }
    }
}

private struct HistoryChart: View {
    let points: [DailyDrinkTotal]
    let range: HistoryRange
    let unitLabel: String

    private var hasData: Bool {
        points.contains { $0.volume > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Volume")
                .font(.headline)

            if hasData {
                Chart(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Volume", point.volume)
                    )
                    .foregroundStyle(by: .value("Drink", point.kind.title))
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    if point.volume > 0 {
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Volume", point.volume)
                        )
                        .foregroundStyle(by: .value("Drink", point.kind.title))
                        .symbolSize(35)
                    }
                }
                .chartForegroundStyleScale(
                    domain: DrinkKind.allCases.map(\.title),
                    range: DrinkKind.allCases.map(\.color)
                )
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(
                        values: .stride(by: .day, count: range.axisDayStride)
                    ) {
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: range.axisDateFormat)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartYAxisLabel(unitLabel)
                .frame(minHeight: 280)
                .accessibilityLabel("Drink volume history")
            } else {
                ContentUnavailableView(
                    "No Drink History",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Drinks added from now on will appear here.")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            }
        }
    }
}

private struct HistoryTotals: View {
    let points: [DailyDrinkTotal]
    let selectedKinds: Set<DrinkKind>
    let unit: SettingsStore.VolumeUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Range Totals")
                .font(.headline)

            ForEach(DrinkKind.allCases.filter(selectedKinds.contains)) { kind in
                LabeledContent {
                    Text(total(for: kind), format: .number.precision(.fractionLength(0...1)))
                        .monospacedDigit()
                    Text(unit.label)
                        .foregroundStyle(.secondary)
                } label: {
                    Label(kind.title, systemImage: kind.symbol)
                        .foregroundStyle(kind.color)
                }
            }
        }
        .padding()
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private func total(for kind: DrinkKind) -> Double {
        points.lazy
            .filter { $0.kind == kind }
            .reduce(0) { $0 + $1.volume }
    }
}

private enum HistoryRange: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case quarter = 90

    var id: Int { rawValue }
    var dayCount: Int { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .week: "7 Days"
        case .month: "30 Days"
        case .quarter: "90 Days"
        }
    }

    var axisDayStride: Int {
        switch self {
        case .week: 1
        case .month: 5
        case .quarter: 14
        }
    }

    var axisDateFormat: Date.FormatStyle {
        switch self {
        case .week:
            .dateTime.weekday(.narrow)
        case .month, .quarter:
            .dateTime.month().day()
        }
    }
}
