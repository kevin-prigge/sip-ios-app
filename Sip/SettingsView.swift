import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    @Environment(\.openURL) private var openURL
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section("Daily Goal") {
                Stepper(value: $settings.goalML, in: 1_000...6_000, step: 100) {
                    LabeledContent("Water goal") {
                        Text(formattedGoal)
                            .monospacedDigit()
                    }
                }
            }

            Section("Units") {
                Picker("Volume", selection: $settings.volumeUnit) {
                    ForEach(SettingsStore.VolumeUnit.allCases) { unit in
                        Text(unit == .cups ? "Cups" : unit.label).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Appearance") {
                Picker("Appearance", selection: $settings.appearance) {
                    Text("System").tag(SettingsStore.Appearance.system)
                    Text("Light").tag(SettingsStore.Appearance.light)
                    Text("Dark").tag(SettingsStore.Appearance.dark)
                }
                .pickerStyle(.segmented)
            }

            Section {
                Toggle("Reminders", isOn: remindersEnabledBinding)

                if settings.enabled && authorizationStatus == .authorized {
                    ForEach(settings.reminderTimesMinutes.indices, id: \.self) { index in
                        HStack {
                            Toggle(
                                "Enable reminder",
                                isOn: reminderEnabledBinding(for: index)
                            )
                            .labelsHidden()
                            .accessibilityLabel("Enable reminder")

                            DatePicker(
                                "Reminder",
                                selection: reminderDateBinding(for: index),
                                displayedComponents: .hourAndMinute
                            )
                        }
                    }
                    .onDelete(perform: removeReminders)

                    Button {
                        settings.addReminder()
                        Task { await rescheduleReminders() }
                    } label: {
                        Label("Add Reminder", systemImage: "plus")
                    }
                }

                if authorizationStatus == .denied {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Notifications are turned off", systemImage: "bell.slash")
                            .foregroundStyle(.red)
                        Button("Open Settings") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                        }
                    }
                }
            } header: {
                Text("Reminders")
            } footer: {
                if settings.enabled && authorizationStatus == .authorized {
                    Text("Sip will remind you at each enabled time.")
                }
            }
        }
        .navigationTitle("Settings")
        .task {
            NotificationManager.shared.configure()
            authorizationStatus = await NotificationManager.shared.authorizationStatus()
            if authorizationStatus == .authorized {
                await rescheduleReminders()
            }
        }
    }

    private var formattedGoal: String {
        let value = settings.goalML / settings.volumeUnit.mlPerUnit
        if settings.volumeUnit == .ounces {
            return "\(Int(value.rounded())) \(settings.volumeUnit.label)"
        }
        return value.formatted(.number.precision(.fractionLength(1))) + " " + settings.volumeUnit.label
    }

    private var remindersEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.enabled },
            set: { isEnabled in
                settings.enabled = isEnabled
                Task {
                    if isEnabled {
                        let granted = await NotificationManager.shared.requestPermission()
                        authorizationStatus = await NotificationManager.shared.authorizationStatus()
                        if !granted {
                            settings.enabled = false
                        }
                    }
                    await rescheduleReminders()
                }
            }
        )
    }

    private func reminderEnabledBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { settings.reminderEnabled[index] },
            set: { isEnabled in
                settings.reminderEnabled[index] = isEnabled
                Task { await rescheduleReminders() }
            }
        )
    }

    private func reminderDateBinding(for index: Int) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    byAdding: .minute,
                    value: settings.reminderTimesMinutes[index],
                    to: Calendar.current.startOfDay(for: .now)
                ) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.reminderTimesMinutes[index] =
                    (components.hour ?? 0) * 60 + (components.minute ?? 0)
                Task { await rescheduleReminders() }
            }
        )
    }

    private func removeReminders(at offsets: IndexSet) {
        settings.removeReminders(at: offsets)
        Task { await rescheduleReminders() }
    }

    private func rescheduleReminders() async {
        let manager = NotificationManager.shared
        manager.clearScheduled()

        guard settings.enabled, authorizationStatus == .authorized else { return }

        let times = zip(settings.currentReminderTimes, settings.reminderEnabled)
            .compactMap { time, isEnabled in isEnabled ? time : nil }
        manager.scheduleDaily(times: times)
    }
}
