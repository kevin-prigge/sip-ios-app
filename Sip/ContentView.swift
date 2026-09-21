import SwiftUI

struct ContentView: View {
    @StateObject private var settings = SettingsStore()
    @State private var drinkLog = DrinkLogStore()

    @Environment(\.scenePhase) private var scenePhase
    @State private var todayML = 0.0
    @State private var drinkCounts: [DrinkKind: Int] = [:]
    @State private var showingAddDrink = false
    @State private var lastAddedDrink: DrinkKind?
    @State private var errorMessage: String?
    @State private var feedbackTrigger = 0

    private var caffeineAdjustmentOunces: Int {
        ((count(for: .soda) + count(for: .coffee)) / 2) * 8
    }

    private var alcoholAdjustmentOunces: Int {
        count(for: .alcohol) * 8
    }

    private var totalAdjustmentOunces: Int {
        caffeineAdjustmentOunces + alcoholAdjustmentOunces
    }

    private var adjustedGoalML: Double {
        settings.goalML + Double(totalAdjustmentOunces) * MeasurementConstants.millilitersPerOunce
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Today") {
                    HydrationSummaryCard(
                        amountML: todayML,
                        baseGoalML: settings.goalML,
                        adjustedGoalML: adjustedGoalML,
                        adjustmentOunces: totalAdjustmentOunces,
                        unit: settings.volumeUnit
                    )
                }

                Section {
                    Button {
                        showingAddDrink = true
                    } label: {
                        Label("Add Drink", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                }

                Section("Quick Add Water") {
                    QuickAddWaterView(unit: settings.volumeUnit) { milliliters in
                        addDrink(.water, milliliters: milliliters)
                    }
                }

                if !drinkCounts.isEmpty {
                    Section("Today’s Drinks") {
                        ForEach(DrinkKind.allCases) { kind in
                            let count = count(for: kind)
                            if count > 0 {
                                DrinkCountRow(kind: kind, count: count)
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image("SIPHeaderIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 40)
                        .accessibilityLabel("Sip")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        HistoryView(
                            drinkLog: drinkLog,
                            unit: settings.volumeUnit
                        )
                    } label: {
                        Label("History", systemImage: "chart.xyaxis.line")
                    }

                    NavigationLink {
                        SettingsView(settings: settings)
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingAddDrink) {
                AddDrinkSheet(settings: settings) { kind, milliliters in
                    addDrink(kind, milliliters: milliliters)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .overlay(alignment: .top) {
                if let lastAddedDrink {
                    AddedDrinkBanner(kind: lastAddedDrink)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .alert("Couldn’t Add Drink", isPresented: errorAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
            .task {
                configureNotificationActions()
                await refresh()
                loadDrinkCounts()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task {
                    await refresh()
                    loadDrinkCounts()
                }
            }
            .refreshable {
                await refresh()
                loadDrinkCounts()
            }
            .sensoryFeedback(.success, trigger: feedbackTrigger)
            .preferredColorScheme(preferredColorScheme)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func count(for kind: DrinkKind) -> Int {
        drinkCounts[kind, default: 0]
    }

    private func configureNotificationActions() {
        let manager = NotificationManager.shared
        manager.configure()
        manager.onQuickAdd8 = { addDrink(.water, milliliters: 8 * MeasurementConstants.millilitersPerOunce) }
        manager.onQuickAdd16 = { addDrink(.water, milliliters: 16 * MeasurementConstants.millilitersPerOunce) }
        manager.onQuickAdd32 = { addDrink(.water, milliliters: 32 * MeasurementConstants.millilitersPerOunce) }
    }

    private func addDrink(_ kind: DrinkKind, milliliters: Double) {
        Task {
            do {
                if kind.usesHealthKit {
                    try await HealthKitManager.shared.requestAuthorization()
                }

                switch kind {
                case .water:
                    try await HealthKitManager.shared.addWater(mL: milliliters)
                case .sportsDrink:
                    try await HealthKitManager.shared.addWater(mL: milliliters * 0.5)
                case .soda:
                    try await HealthKitManager.shared.addCaffeine(
                        mg: milliliters / MeasurementConstants.millilitersPerOunce * (35.0 / 12.0)
                    )
                case .coffee:
                    try await HealthKitManager.shared.addCaffeine(
                        mg: milliliters / MeasurementConstants.millilitersPerOunce * 12.0
                    )
                case .alcohol:
                    break
                }

                drinkCounts[kind, default: 0] += 1
                drinkLog.add(kind: kind, volumeML: milliliters)
                saveDrinkCounts()
                await refresh()
                showConfirmation(for: kind)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func refresh() async {
        todayML = (try? await HealthKitManager.shared.todayTotalML()) ?? 0
    }

    private func showConfirmation(for kind: DrinkKind) {
        feedbackTrigger += 1
        withAnimation {
            lastAddedDrink = kind
        }

        Task {
            try? await Task.sleep(for: .seconds(2))
            guard lastAddedDrink == kind else { return }
            withAnimation {
                lastAddedDrink = nil
            }
        }
    }

    private func todayKey(for kind: DrinkKind) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return "sip.drinks.\(kind.rawValue).\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private func loadDrinkCounts() {
        let defaults = UserDefaults.standard
        drinkCounts = Dictionary(
            uniqueKeysWithValues: DrinkKind.allCases.compactMap { kind in
                let count = defaults.integer(forKey: todayKey(for: kind))
                return count > 0 ? (kind, count) : nil
            }
        )
    }

    private func saveDrinkCounts() {
        let defaults = UserDefaults.standard
        for kind in DrinkKind.allCases {
            defaults.set(count(for: kind), forKey: todayKey(for: kind))
        }
    }
}

private struct HydrationSummaryCard: View {
    let amountML: Double
    let baseGoalML: Double
    let adjustedGoalML: Double
    let adjustmentOunces: Int
    let unit: SettingsStore.VolumeUnit

    private var progress: Double {
        guard adjustedGoalML > 0 else { return 0 }
        return min(amountML / adjustedGoalML, 1)
    }

    private var remainingML: Double {
        max(adjustedGoalML - amountML, 0)
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.15), lineWidth: 16)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(colors: [.blue, .cyan, .blue], center: .center),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: progress)

                VStack(spacing: 3) {
                    Text(formatted(amountML))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    Text("of \(formatted(adjustedGoalML))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 190, height: 190)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(formatted(amountML)) of \(formatted(adjustedGoalML))")

            VStack(spacing: 6) {
                if progress >= 1 {
                    Label("Daily goal reached", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                } else {
                    Text("\(formatted(remainingML)) remaining")
                        .font(.headline)
                }

                if adjustmentOunces > 0 {
                    Label(
                        "Today’s goal includes \(adjustmentOunces) oz of drink adjustments",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                } else {
                    Text("Base goal: \(formatted(baseGoalML))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func formatted(_ milliliters: Double) -> String {
        let value = milliliters / unit.mlPerUnit
        if unit == .ounces {
            return "\(Int(value.rounded())) \(unit.label)"
        }
        return value.formatted(.number.precision(.fractionLength(1))) + " " + unit.label
    }
}

private struct QuickAddWaterView: View {
    let unit: SettingsStore.VolumeUnit
    let onAdd: (Double) -> Void

    private let amounts = [8, 12, 16]

    var body: some View {
        ViewThatFits {
            HStack {
                buttons
            }

            VStack {
                buttons
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        ForEach(amounts, id: \.self) { ounces in
            Button {
                onAdd(Double(ounces) * MeasurementConstants.millilitersPerOunce)
            } label: {
                Text(displayAmount(forOunces: ounces))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .accessibilityLabel("Add \(displayAmount(forOunces: ounces)) of water")
        }
    }

    private func displayAmount(forOunces ounces: Int) -> String {
        let value = Double(ounces) * MeasurementConstants.millilitersPerOunce / unit.mlPerUnit
        if unit == .ounces {
            return "\(ounces) oz"
        }
        return value.formatted(.number.precision(.fractionLength(1))) + " " + unit.label
    }
}

private struct DrinkCountRow: View {
    let kind: DrinkKind
    let count: Int

    var body: some View {
        LabeledContent {
            Text(count, format: .number)
                .monospacedDigit()
        } label: {
            Label(kind.title, systemImage: kind.symbol)
                .foregroundStyle(kind.color)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AddedDrinkBanner: View {
    let kind: DrinkKind

    var body: some View {
        Label("\(kind.title) added", systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 6, y: 2)
    }
}

enum DrinkKind: String, CaseIterable, Codable, Identifiable {
    case water
    case sportsDrink
    case soda
    case coffee
    case alcohol

    var id: String { rawValue }

    var title: String {
        switch self {
        case .water: "Water"
        case .sportsDrink: "Sports Drink"
        case .soda: "Soda"
        case .coffee: "Coffee"
        case .alcohol: "Alcohol"
        }
    }

    var symbol: String {
        switch self {
        case .water: "drop.fill"
        case .sportsDrink: "figure.run"
        case .soda: "takeoutbag.and.cup.and.straw.fill"
        case .coffee: "mug.fill"
        case .alcohol: "wineglass.fill"
        }
    }

    var color: Color {
        switch self {
        case .water: .blue
        case .sportsDrink: .orange
        case .soda: .red
        case .coffee: .brown
        case .alcohol: .purple
        }
    }

    var usesHealthKit: Bool {
        self != .alcohol
    }

    var presetOunces: [Int] {
        switch self {
        case .water: [8, 12, 16]
        case .sportsDrink: [12, 20, 28]
        case .soda: [12, 20]
        case .coffee: [8, 12, 16]
        case .alcohol: [5, 12, 16]
        }
    }

    var detail: String {
        switch self {
        case .water:
            "Counts fully toward hydration."
        case .sportsDrink:
            "Half the volume counts toward hydration."
        case .soda, .coffee:
            "Every two caffeinated drinks add 8 oz to today’s water goal."
        case .alcohol:
            "Each drink adds 8 oz to today’s water goal."
        }
    }
}

struct AddDrinkSheet: View {
    @ObservedObject var settings: SettingsStore
    let onAdd: (DrinkKind, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind = DrinkKind.water
    @State private var amount = 12.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Drink") {
                    Picker("Type", selection: $kind) {
                        ForEach(DrinkKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.symbol)
                                .tag(kind)
                        }
                    }

                    Text(kind.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Amount") {
                    HStack {
                        ForEach(kind.presetOunces, id: \.self) { ounces in
                            Button(displayAmount(forOunces: ounces)) {
                                amount = displayValue(forOunces: ounces)
                            }
                            .buttonStyle(.bordered)
                            .tint(isSelected(ounces) ? kind.color : .secondary)
                            .frame(maxWidth: .infinity)
                        }
                    }

                    Stepper(value: $amount, in: amountRange, step: amountStep) {
                        LabeledContent("Custom") {
                            Text(formattedAmount)
                                .monospacedDigit()
                        }
                    }
                }

                Section {
                    Button {
                        onAdd(kind, amount * settings.volumeUnit.mlPerUnit)
                        dismiss()
                    } label: {
                        Label("Add \(kind.title) — \(formattedAmount)", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(kind.color)
                }
            }
            .navigationTitle("Add Drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: kind) { _, newKind in
                amount = displayValue(forOunces: newKind.presetOunces.first ?? 12)
            }
        }
    }

    private var amountRange: ClosedRange<Double> {
        switch settings.volumeUnit {
        case .ounces: 1...44
        case .liters: 0.05...2
        case .cups: 0.1...6
        }
    }

    private var amountStep: Double {
        switch settings.volumeUnit {
        case .ounces: 1
        case .liters: 0.05
        case .cups: 0.1
        }
    }

    private var formattedAmount: String {
        if settings.volumeUnit == .ounces {
            return "\(Int(amount.rounded())) \(settings.volumeUnit.label)"
        }
        return amount.formatted(.number.precision(.fractionLength(1))) + " " + settings.volumeUnit.label
    }

    private func displayValue(forOunces ounces: Int) -> Double {
        Double(ounces) * MeasurementConstants.millilitersPerOunce / settings.volumeUnit.mlPerUnit
    }

    private func displayAmount(forOunces ounces: Int) -> String {
        let value = displayValue(forOunces: ounces)
        if settings.volumeUnit == .ounces {
            return "\(ounces) oz"
        }
        return value.formatted(.number.precision(.fractionLength(1))) + " " + settings.volumeUnit.label
    }

    private func isSelected(_ ounces: Int) -> Bool {
        abs(amount - displayValue(forOunces: ounces)) < 0.01
    }
}

private enum MeasurementConstants {
    static let millilitersPerOunce = 29.5735
}
