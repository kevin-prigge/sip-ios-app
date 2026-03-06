//
//  ContentView.swift
//  Sip
//
//  Created by Kevin Prigge on 10/1/25.
//

import SwiftUI
import UserNotifications

extension Notification.Name {
    static let hydrationQuickAdd = Notification.Name("HydrationQuickAdd")
}

final class AppNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationManager()

    private override init() { super.init() }

    func setupCategories() {
        let quickAdd4 = UNNotificationAction(
            identifier: "quickAdd4oz",
            title: "+4 oz 💧",
            options: []
        )
        let quickAdd8 = UNNotificationAction(
            identifier: "quickAdd8oz",
            title: "+8 oz 💧",
            options: []
        )
        let quickAdd12 = UNNotificationAction(
            identifier: "quickAdd12oz",
            title: "+12 oz 💧",
            options: []
        )
        let quickAdd16 = UNNotificationAction(
            identifier: "quickAdd16oz",
            title: "+16 oz 💧",
            options: []
        )

        let hydrationCategory = UNNotificationCategory(
            identifier: "hydrationCategory",
            actions: [quickAdd4, quickAdd8, quickAdd12, quickAdd16],
            intentIdentifiers: [],
            options: []
        )

        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([hydrationCategory])
        center.delegate = self
    }

    // Handle action taps
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let ounces: Int? = {
            switch response.actionIdentifier {
            case "quickAdd4oz": return 4
            case "quickAdd8oz": return 8
            case "quickAdd12oz": return 12
            case "quickAdd16oz": return 16
            default: return nil
            }
        }()

        if let ounces {
            NotificationCenter.default.post(name: .hydrationQuickAdd,
                                            object: nil,
                                            userInfo: ["ounces": ounces])
        }
        completionHandler()
    }
}

struct ContentView: View {
    @StateObject private var settings = SettingsStore()
    @State private var todayML: Double = 0
    @State private var todayDrinks: Int = 0
    @State private var todaySoda: Int = 0
    @State private var todayCoffee: Int = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var midnightTimer: Timer? = nil
    @State private var showingAddCard: Bool = false
    @State private var reachedGoal: Bool = false

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
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
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
                                    saveCaffeineCounts()
                                    // Approximate caffeine: ~2.9 mg/oz
                                    let mgPerOz = 35.0 / 12.0
                                    let mg = Double(baseOz) * mgPerOz
                                    Task { try? await HealthKitManager.shared.addCaffeine(mg: mg) }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
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
                                saveCaffeineCounts()
                                // Approximate caffeine: ~12 mg/oz
                                let mgPerOz = 96.0 / 8.0
                                let mg = Double(baseOz) * mgPerOz
                                Task { try? await HealthKitManager.shared.addCaffeine(mg: mg) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.brown)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }

                        // Centered Add button for additional entry point
                        HStack {
                            Spacer()
                            Button {
                                showingAddCard = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                        .font(.headline)
                                    Text("Add Drink")
                                        .font(.headline)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.glassProminent)
                            .contentShape(Rectangle())
                            Spacer()
                        }
                        .padding(.top, 4)
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
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .hydrationQuickAdd)) { note in
                guard let ounces = note.userInfo?["ounces"] as? Int else { return }
                let ml = Double(ounces) * 29.574
                Task {
                    try? await HealthKitManager.shared.addWater(mL: ml)
                    await MainActor.run {
                        todayDrinks += 1
                    }
                    await refresh()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingAddCard = true
                    } label: {
                        Image(showingAddCard ? "SIPHeaderIcon2" : "SIPHeaderIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 54)
                            .accessibilityLabel("Add drink")
                    }
                    .contentShape(Rectangle())
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddCard = true
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Add drink")
                    }
                }
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
                        saveCaffeineCounts()
                        let oz = amount * settings.volumeUnit.mlPerUnit / 29.574
                        let mgPerOz = 35.0 / 12.0
                        let mg = oz * mgPerOz
                        Task { try? await HealthKitManager.shared.addCaffeine(mg: mg) }
                    case .coffee:
                        todayCoffee += 1
                        saveCaffeineCounts()
                        let oz = amount * settings.volumeUnit.mlPerUnit / 29.574
                        let mgPerOz = 96.0 / 8.0
                        let mg = oz * mgPerOz
                        Task { try? await HealthKitManager.shared.addCaffeine(mg: mg) }
                    }
                }
                .presentationDetents([.height(300), .medium])
                .presentationDragIndicator(.visible)
            }
            .task {
                do { try await HealthKitManager.shared.requestAuthorization() } catch { }
                AppNotificationManager.shared.setupCategories()
                // When scheduling a local notification, set: content.categoryIdentifier = "hydrationCategory"
                await refresh()
                await MainActor.run { loadCaffeineCounts() }
                await MainActor.run { scheduleMidnightRefresh() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { @MainActor in
                        midnightTimer?.invalidate()
                        scheduleMidnightRefresh()
                        loadCaffeineCounts()
                    }
                    Task { await refresh() }
                }
            }
            .refreshable { await refresh() }
            .sensoryFeedback(.success, trigger: reachedGoal)
            .preferredColorScheme({
                switch settings.appearance {
                case .system: return nil
                case .light: return .light
                case .dark: return .dark
                }
            }())
        }
    }

    @MainActor
    private func refresh() async {
        let ml = (try? await HealthKitManager.shared.todayTotalML()) ?? 0
        todayML = ml
        todayDrinks = (try? await HealthKitManager.shared.todaySampleCount()) ?? 0
        let didReach = todayML >= adjustedGoalML
        if didReach && !reachedGoal { reachedGoal = true }
    }

    private func todayKey(_ kind: String) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        return "sip.\(kind).\(y)-\(m)-\(d)"
    }

    @MainActor
    private func loadCaffeineCounts() {
        let defaults = UserDefaults.standard
        todaySoda = defaults.integer(forKey: todayKey("soda"))
        todayCoffee = defaults.integer(forKey: todayKey("coffee"))
    }

    @MainActor
    private func saveCaffeineCounts() {
        let defaults = UserDefaults.standard
        defaults.set(todaySoda, forKey: todayKey("soda"))
        defaults.set(todayCoffee, forKey: todayKey("coffee"))
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
                    saveCaffeineCounts()
                }
            }
            Task { @MainActor in
                scheduleMidnightRefresh()
            }
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
        HStack(spacing: 12) {
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

                // Inner caffeine ring (shows caffeinated share and split into soda (red) and coffee (brown))
                let totalDrinks = drinkCounts.water + drinkCounts.soda + drinkCounts.coffee
                let sodaFrac: Double = totalDrinks > 0 ? Double(drinkCounts.soda) / Double(totalDrinks) : 0
                let coffeeFrac: Double = totalDrinks > 0 ? Double(drinkCounts.coffee) / Double(totalDrinks) : 0

                // Track for inner ring
                Circle()
                    .stroke(.secondary.opacity(0.15), lineWidth: 10)
                    .padding(13)

                // Soda segment
                if sodaFrac > 0 {
                    Circle()
                        .trim(from: 0, to: min(sodaFrac, 1))
                        .stroke(.red, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(13)
                        .animation(.easeInOut(duration: 0.35), value: drinkCounts.soda)
                }

                // Coffee segment
                if coffeeFrac > 0 {
                    Circle()
                        .trim(from: min(sodaFrac, 1), to: min(sodaFrac + coffeeFrac, 1))
                        .stroke(.brown, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(13)
                        .animation(.easeInOut(duration: 0.35), value: drinkCounts.coffee)
                }

                VStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.blue)
                    VStack(spacing: 2) {
                        Text(showsDecimal ? String(format: "%.1f", amountValue) : String(Int(amountValue)))
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        if progress >= 1.0 {
                            Text("you did it! 🎉")
                                .font(.footnote)
                                .foregroundStyle(.green)
                        } else {
                            Text(showsDecimal ? String(format: "of %.1f %@", goalValue + bonusValue, unitLabel) : "of \(Int(goalValue + bonusValue)) \(unitLabel)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                }
            }
            .frame(minWidth: 120, minHeight: 120)

            VStack(alignment: .leading, spacing: 8) {
                Text("Drinks Today")
                    .font(.headline)
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "waterbottle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.blue)
                        Text("x \(drinkCounts.water)")
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 4) {
                        Image(systemName: "waterbottle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.red)
                        Text("x \(drinkCounts.soda)")
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 4) {
                        Image(systemName: "mug.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.brown)
                        Text("x \(drinkCounts.coffee)")
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
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

            HStack(spacing: 12) {
                Button {
                    isPresentingAdd = true
                } label: {
                    Image(isPresentingAdd ? "SIPHeaderIcon2" : "SIPHeaderIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(height: height)
                        .accessibilityLabel("Add drink")
                }
            }
            .position(x: x, y: bigHeight / 2)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: progress)
        }
        .frame(height: 100)
        .padding(.vertical, 6)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 0))
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
    @State private var didAdd: Bool = false

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
                        didAdd.toggle()
                        onAdd(kind, amount)
                        isPresented = false
                    }
                    .disabled(amount <= 0)
                    .sensoryFeedback(.success, trigger: didAdd)
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

