import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @State private var notifGranted: Bool? = nil
    @State private var showReminderSettings: Bool = false
    @State private var showingTimesHelp: Bool = false

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

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Volume", selection: $settings.volumeUnit) {
                        ForEach(SettingsStore.VolumeUnit.allCases) { unit in
                            Text(unit == .cups ? "Cups" : unit.label).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
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
            .navigationTitle("Settings")
            .task {
                NotificationManager.shared.configure()
                let granted = await NotificationManager.shared.requestPermission()
                notifGranted = granted
                await rescheduleReminders(enabled: settings.enabled, force: false)
            }
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
}
