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
    @State private var notifGranted: Bool? = nil
    @State private var showingTimesHelp = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var midnightTimer: Timer? = nil
    @State private var showReminderSettings: Bool = false

    private var bonusPairs: Int { (todaySoda + todayCoffee) / 2 }
    private var bonusOunces: Int { bonusPairs * 8 }
    private var adjustedGoalML: Double { settings.goalML + Double(bonusOunces) * 29.574 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Today") {
                    TodayRing(
                        progress: min(todayML / adjustedGoalML, 1.0),
                        ounces: Int(todayML / 29.574),
                        goalOunces: Int(settings.goalML / 29.574),
                        bonusOunces: bonusOunces,
                        drinkCounts: (water: todayDrinks, soda: todaySoda, coffee: todayCoffee)
                    )
                }

                Section("Quick Add") {
                    VStack(alignment: .leading, spacing: 8) {
                        // Water row: 4, 8, 12, 16 oz (blue)
                        HStack {
                            ForEach([4, 8, 12, 16], id: \.self) { oz in
                                Button("+\(oz) oz") {
                                    Task {
                                        let ml = Double(oz) * 29.574
                                        try? await HealthKitManager.shared.addWater(mL: ml)
                                        await MainActor.run { todayDrinks += 1 }
                                        await refresh()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                            }
                        }
                        // Soda row: 12, 20 oz (red)
                        HStack {
                            ForEach([12, 20], id: \.self) { oz in
                                Button("+\(oz) oz") {
                                    todaySoda += 1
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                        // Coffee row: 8 oz (brown)
                        HStack {
                            Button("+8 oz") {
                                todayCoffee += 1
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.brown)
                        }
                    }
                }

                Section("Daily Goal") {
                    Stepper(value: $settings.goalML, in: 1000...6000, step: 100) {
                        Text("\(Int(settings.goalML / 29.574)) oz + \(bonusOunces) oz")
                    }
                }

                Section("Reminders") {
                    Toggle("Enable reminders", isOn: $settings.enabled)
                        .onChange(of: settings.enabled) { _, on in
                            Task { await rescheduleReminders(enabled: on) }
                        }

                    DisclosureGroup(isExpanded: $showReminderSettings) {
                        VStack(spacing: 8) {
                            ForEach(0..<6, id: \.self) { idx in
                                HStack {
                                    Toggle(isOn: Binding(
                                        get: { settings.reminderEnabled[idx] },
                                        set: { newVal in
                                            settings.reminderEnabled[idx] = newVal
                                            Task { await rescheduleReminders(enabled: settings.enabled) }
                                        }
                                    )) { EmptyView() }
                                    .toggleStyle(.switch)
                                    .frame(width: 60)

                                    let minutesBinding = Binding<Int>(
                                        get: { settings.reminderTimesMinutes[idx] },
                                        set: { newVal in
                                            settings.reminderTimesMinutes[idx] = max(0, min(23*60+59, newVal))
                                            Task { await rescheduleReminders(enabled: settings.enabled) }
                                        }
                                    )

                                    // 12-hour bindings
                                    let hour12Binding = Binding<Int>(
                                        get: {
                                            let h24 = minutesBinding.wrappedValue / 60
                                            let h12 = h24 % 12
                                            return h12 == 0 ? 12 : h12
                                        },
                                        set: { h12 in
                                            let minute = minutesBinding.wrappedValue % 60
                                            let pm = (minutesBinding.wrappedValue / 60) >= 12
                                            var hour = h12 % 12 // 0..11
                                            if pm { hour += 12 }
                                            minutesBinding.wrappedValue = hour * 60 + minute
                                        }
                                    )

                                    let isPMBinding = Binding<Bool>(
                                        get: { (minutesBinding.wrappedValue / 60) >= 12 },
                                        set: { pm in
                                            let minute = minutesBinding.wrappedValue % 60
                                            var hour = (minutesBinding.wrappedValue / 60) % 12 // 0..11
                                            if pm { hour += 12 }
                                            minutesBinding.wrappedValue = hour * 60 + minute
                                        }
                                    )

                                    HStack(spacing: 8) {
                                        Picker("", selection: hour12Binding) {
                                            ForEach(1...12, id: \.self) { Text("\($0)") }
                                        }
                                        .pickerStyle(.menu)
                                        .labelsHidden()

                                        Text(":")

                                        Picker("", selection: Binding(
                                            get: { minutesBinding.wrappedValue % 60 },
                                            set: { minute in
                                                minutesBinding.wrappedValue = (minutesBinding.wrappedValue / 60) * 60 + minute
                                            }
                                        )) {
                                            ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)) }
                                        }
                                        .pickerStyle(.menu)
                                        .labelsHidden()

                                        Picker("", selection: isPMBinding) {
                                            Text("AM").tag(false)
                                            Text("PM").tag(true)
                                        }
                                        .pickerStyle(.segmented)
                                        .labelsHidden()
                                        .frame(maxWidth: 140)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        Text("Notification Times")
                    }
                    .disabled(!(notifGranted ?? false))

                    if let granted = notifGranted {
                        Label(granted ? "Notifications allowed" : "Notifications not allowed",
                              systemImage: granted ? "bell.badge.fill" : "bell.slash")
                            .foregroundStyle(granted ? .green : .red)
                    }

                    Button("What times?") { showingTimesHelp = true }
                        .buttonStyle(.borderless)
                }
            }
            .navigationTitle("Sip")
            .task {
                NotificationManager.shared.configure()
                let granted = await NotificationManager.shared.requestPermission()
                notifGranted = granted
                do { try await HealthKitManager.shared.requestAuthorization() } catch { }
                await refresh()
                scheduleMidnightRefresh()
                await rescheduleReminders(enabled: settings.enabled, force: false)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    midnightTimer?.invalidate()
                    scheduleMidnightRefresh()
                    Task { await refresh() }
                }
            }
            .refreshable { await refresh() }
            .alert("Reminder Times",
                   isPresented: $showingTimesHelp,
                   actions: { Button("OK", role: .cancel) { } },
                   message: {
                       let enabledTimes = zip(settings.currentReminderTimes, settings.reminderEnabled)
                           .enumerated()
                           .compactMap { _, pair -> String? in
                               let (dc, isOn) = pair
                               guard isOn, let h = dc.hour, let m = dc.minute else { return nil }
                               let isPM = h >= 12
                               var hour12 = h % 12
                               if hour12 == 0 { hour12 = 12 }
                               let suffix = isPM ? "PM" : "AM"
                               return String(format: "%d:%02d %@", hour12, m, suffix)
                           }
                           .joined(separator: ", ")
                       return Text(enabledTimes.isEmpty ? "No times enabled." : enabledTimes)
                   })
        }
    }

    @MainActor
    private func refresh() async {
        let ml = (try? await HealthKitManager.shared.todayTotalML()) ?? 0
        todayML = ml
        todayDrinks = (try? await HealthKitManager.shared.todaySampleCount()) ?? 0
    }

    @MainActor
    private func rescheduleReminders(enabled: Bool, force: Bool = false) async {
        guard notifGranted == true else { return }
        let mgr = NotificationManager.shared
        mgr.clearScheduled()
        if enabled || force {
            let times = zip(settings.currentReminderTimes, settings.reminderEnabled).compactMap { dc, isOn in
                isOn ? dc : nil
            }
            if !times.isEmpty {
                mgr.scheduleDaily(times: times)
            }
        }
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
    let ounces: Int
    let goalOunces: Int
    let bonusOunces: Int
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
                        Text("\(ounces)")
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .monospacedDigit()
                        Text("of \(goalOunces + bonusOunces) oz")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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

