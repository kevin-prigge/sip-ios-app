//
//  ContentView.swift
//  Sip
//
//  Created by Kevin Prigge on 10/1/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var settings = SettingsStore()
    @State private var todayML: Double = 0
    @State private var todayDrinks: Int = 0
    @State private var todaySoda: Int = 0
    @State private var todayCoffee: Int = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var midnightTimer: Timer? = nil
    @State private var headerCollapse: CGFloat = 0
    @State private var showingAddCard: Bool = false

    private var bonusPairs: Int { (todaySoda + todayCoffee) / 2 }
    private var bonusOunces: Int { bonusPairs * 8 }
    private var adjustedGoalML: Double { settings.goalML + Double(bonusOunces) * 29.574 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Today") {
                    let unit = settings.volumeUnit
                    let mlPerUnit = unit.mlPerUnit
                    let amountValue = todayML / mlPerUnit
                    let goalValue = settings.goalML / mlPerUnit
                    let bonusValue: Double = {
                        switch unit {
                        case .ounces: return Double(bonusOunces)
                        case .liters: return Double(bonusOunces) * 29.574 / 1000.0
                        case .cups: return Double(bonusOunces) / 8.0
                        }
                    }()
                    let unitLabel = (unit == .cups) ? "cups" : unit.label
                    let showsDecimal = (unit == .liters || unit == .cups)

                    TodayRing(
                        progress: min(todayML / adjustedGoalML, 1.0),
                        amountValue: amountValue,
                        goalValue: goalValue,
                        bonusValue: bonusValue,
                        unitLabel: unitLabel,
                        showsDecimal: showsDecimal,
                        drinkCounts: (water: todayDrinks, soda: todaySoda, coffee: todayCoffee)
                    )
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: proxy.frame(in: .named("scroll")).minY
                                )
                        }
                    )
                }
                
                Section {
                    Button {
                        showingAddCard = true
                    } label: {
                        Text("Add Drink")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.large)
                }

                Section("Quick Add") {
                    VStack(alignment: .leading, spacing: 8) {
                        let unit = settings.volumeUnit
                        let unitLabel = (unit == .cups) ? "cups" : unit.label

                        // Water row: 4, 8, 12, 16 oz (blue)
                        HStack {
                            ForEach([4, 8, 12, 16], id: \.self) { baseOz in
                                let ml = Double(baseOz) * 29.574
                                let display = ml / unit.mlPerUnit
                                let title: String = {
                                    if unit == .cups || unit == .liters {
                                        return String(format: "+%.1f %@", display, unitLabel)
                                    } else {
                                        return "+\(Int(display)) \(unitLabel)"
                                    }
                                }()
                                Button(title) {
                                    Task {
                                        try? await HealthKitManager.shared.addWater(mL: ml)
                                        await MainActor.run {
                                            todayDrinks += 1
                                        }
                                        await refresh()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                            }
                        }
                        // Soda row: 12, 20 oz (red)
                        HStack {
                            ForEach([12, 20], id: \.self) { baseOz in
                                let ml = Double(baseOz) * 29.574
                                let display = ml / unit.mlPerUnit
                                let title: String = {
                                    if unit == .cups || unit == .liters {
                                        return String(format: "+%.1f %@", display, unitLabel)
                                    } else {
                                        return "+\(Int(display)) \(unitLabel)"
                                    }
                                }()
                                Button(title) {
                                    todaySoda += 1
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                        // Coffee row: 8 oz (brown)
                        HStack {
                            let baseOz = 8
                            let ml = Double(baseOz) * 29.574
                            let display = ml / unit.mlPerUnit
                            let title: String = {
                                if unit == .cups || unit == .liters {
                                    return String(format: "+%.1f %@", display, unitLabel)
                                } else {
                                    return "+\(Int(display)) \(unitLabel)"
                                }
                            }()
                            Button(title) {
                                todayCoffee += 1
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.brown)
                        }
                    }
                }

                Section("Daily Goal") {
                    Stepper(value: $settings.goalML, in: 1000...6000, step: 100) {
                        let unit = settings.volumeUnit
                        let goalVal = settings.goalML / unit.mlPerUnit
                        let bonusVal: Double = {
                            switch unit {
                            case .ounces: return Double(bonusOunces)
                            case .liters: return Double(bonusOunces) * 29.574 / 1000.0
                            case .cups: return Double(bonusOunces) / 8.0
                            }
                        }()
                        let unitLabel = (unit == .cups) ? "cups" : unit.label
                        let showsDecimal = (unit == .liters || unit == .cups)
                        if showsDecimal {
                            Text(String(format: "%.1f %@ + %.1f %@", goalVal, unitLabel, bonusVal, unitLabel))
                        } else {
                            Text("\(Int(goalVal)) \(unitLabel) + \(Int(bonusVal)) \(unitLabel)")
                        }
                    }
                }
                
                Section {
                    NavigationLink(destination: SettingsView(settings: settings)) {
                        Label("Settings", systemImage: "gear")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.gray)
                    .controlSize(.large)
                }
            }
            .coordinateSpace(name: "scroll")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) {
                CollapsingHeader(progress: headerCollapse, isPresentingAdd: $showingAddCard)
            }
            .sheet(isPresented: $showingAddCard) {
                AddDrinkSheet(settings: settings, isPresented: $showingAddCard) { kind, amount in
                    switch kind {
                    case .water:
                        Task {
                            let ml = amount * settings.volumeUnit.mlPerUnit
                            try? await HealthKitManager.shared.addWater(mL: ml)
                            await MainActor.run { todayDrinks += 1 }
                            await refresh()
                        }
                    case .soda:
                        todaySoda += 1
                    case .coffee:
                        todayCoffee += 1
                    }
                }
                .presentationDetents([.height(300), .medium])
                .presentationDragIndicator(.visible)
            }
            .task {
                do { try await HealthKitManager.shared.requestAuthorization() } catch { }
                await refresh()
                scheduleMidnightRefresh()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    midnightTimer?.invalidate()
                    scheduleMidnightRefresh()
                    Task { await refresh() }
                }
            }
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { y in
                let progress = min(max(-y / 80.0, 0.0), 1.0)
                headerCollapse = progress
            }
            .refreshable { await refresh() }
        }
    }

    @MainActor
    private func refresh() async {
        let ml = (try? await HealthKitManager.shared.todayTotalML()) ?? 0
        todayML = ml
        todayDrinks = (try? await HealthKitManager.shared.todaySampleCount()) ?? 0
    }

    @MainActor
    private func scheduleMidnightRefresh() {
        let cal = Calendar.current
        let components = DateComponents(hour: 0, minute: 0, second: 5)
        let nextMidnight = cal.nextDate(after: .now, matching: components, matchingPolicy: .nextTime) ?? .now.addingTimeInterval(24 * 60 * 60)
        let interval = max(1, nextMidnight.timeIntervalSinceNow)
        midnightTimer?.invalidate()
        midnightTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            Task {
                await refresh()
                await MainActor.run {
                    todaySoda = 0
                    todayCoffee = 0
                }
            }
            scheduleMidnightRefresh()
        }
    }
}

struct TodayRing: View {
    let progress: Double
    let amountValue: Double
    let goalValue: Double
    let bonusValue: Double
    let unitLabel: String
    let showsDecimal: Bool
    let drinkCounts: (water: Int, soda: Int, coffee: Int)

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.2), lineWidth: 16)

                Circle()
                    .trim(from: 0, to: min(progress, 1))
                    .stroke(
                        AngularGradient(gradient: Gradient(colors: [.blue, .cyan, .blue]),
                                        center: .center),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: progress)

                VStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.blue)
                    VStack(spacing: 2) {
                        Text(showsDecimal ? String(format: "%.1f", amountValue) : String(Int(amountValue)))
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .monospacedDigit()
                        if progress >= 1.0 {
                            Text("you did it! 🎉")
                                .font(.footnote)
                                .foregroundStyle(.green)
                        } else {
                            Text(showsDecimal ? String(format: "of %.1f %@", goalValue + bonusValue, unitLabel) : "of \(Int(goalValue + bonusValue)) \(unitLabel)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(width: 140, height: 140)

            VStack(alignment: .leading, spacing: 8) {
                Text("Drinks Today")
                    .font(.headline)
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "waterbottle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.blue)
                        Text("x \(drinkCounts.water)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 6) {
                        Image(systemName: "waterbottle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.red)
                        Text("x \(drinkCounts.soda)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 6) {
                        Image(systemName: "mug.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.brown)
                        Text("x \(drinkCounts.coffee)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct CollapsingHeader: View {
    let progress: CGFloat
    @Binding var isPresentingAdd: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let bigHeight: CGFloat = 90
            let smallHeight: CGFloat = 28
            let height = bigHeight - (bigHeight - smallHeight) * progress
            let centerX = width / 2
            let leadingX = 16 + height / 2
            let x = centerX + (leadingX - centerX) * progress

            Image(isPresentingAdd ? "SIPHeaderIcon2" : "SIPHeaderIcon")
                .resizable()
                .scaledToFit()
                .frame(height: height)
                .accessibilityHidden(false)
                .accessibilityLabel("Add drink")
                .accessibilityAddTraits(.isButton)
                .position(x: x, y: bigHeight / 2)
                .contentShape(Rectangle())
                .onTapGesture { isPresentingAdd = true }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: progress)
        }
        .frame(height: 100)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

enum DrinkKind: String, CaseIterable, Identifiable {
    case water = "Water", soda = "Soda", coffee = "Coffee"
    var id: String { rawValue }
}

struct AddDrinkSheet: View {
    @ObservedObject var settings: SettingsStore
    @Binding var isPresented: Bool
    var onAdd: (DrinkKind, Double) -> Void
    @State private var kind: DrinkKind = .water
    @State private var amount: Double = 12

    private var sliderTint: Color {
        switch kind {
        case .water: return .blue
        case .soda: return .red
        case .coffee: return .brown
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("Drink", selection: $kind) {
                    ForEach(DrinkKind.allCases) { k in
                        Text(k.rawValue).tag(k)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 8) {
                    let unit = settings.volumeUnit
                    let unitLabel = (unit == .cups) ? "cups" : unit.label
                    let maxAmount: Double = {
                        switch unit {
                        case .ounces: return 44
                        case .liters: return 2.0
                        case .cups: return 6
                        }
                    }()
                    let step: Double = {
                        switch unit {
                        case .ounces: return 1
                        case .liters: return 0.05
                        case .cups: return 0.1
                        }
                    }()
                    HStack {
                        Text("Amount")
                        Spacer()
                        Text({
                            if unit == .cups || unit == .liters { return String(format: "%.1f %@", amount, unitLabel) }
                            else { return "\(Int(amount)) \(unitLabel)" }
                        }())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    }
                    Slider(value: $amount, in: 0...maxAmount, step: step)
                        .tint(sliderTint)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Add Drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(kind, amount)
                        isPresented = false
                    }
                    .disabled(amount <= 0)
                }
            }
            .onAppear {
                switch settings.volumeUnit {
                case .ounces: amount = 12
                case .liters: amount = 0.35
                case .cups: amount = 1.5
                }
            }
            .onChange(of: settings.volumeUnit) { _, newUnit in
                switch newUnit {
                case .ounces: amount = 12
                case .liters: amount = 0.35
                case .cups: amount = 1.5
                }
            }
        }
    }
}

