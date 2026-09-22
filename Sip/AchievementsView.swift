import SwiftUI

struct AchievementsView: View {
    let drinkLog: DrinkLogStore
    let goalML: Double
    let unit: SettingsStore.VolumeUnit

    private var summary: AchievementSummary {
        AchievementSummary(events: drinkLog.events, baseGoalML: goalML)
    }

    var body: some View {
        Group {
            if drinkLog.events.isEmpty {
                ContentUnavailableView(
                    "No Achievements Yet",
                    systemImage: "trophy",
                    description: Text("Log your drinks to start building streaks and personal records.")
                )
            } else {
                List {
                    Section("Personal Bests") {
                        AchievementRow(
                            title: "Most water in a day",
                            value: formattedVolume(summary.mostWaterML),
                            systemImage: "drop.fill",
                            color: .blue
                        )
                        AchievementRow(
                            title: "Longest circle streak",
                            value: dayCount(summary.longestCircleStreak),
                            systemImage: "circle.circle.fill",
                            color: .cyan
                        )
                        AchievementRow(
                            title: "Longest tracking streak",
                            value: dayCount(summary.longestTrackingStreak),
                            systemImage: "calendar.badge.checkmark",
                            color: .green
                        )
                    }

                    Section("Healthy Habits") {
                        AchievementRow(
                            title: "Caffeine-free circle days",
                            value: dayCount(summary.caffeineFreeCircleDays),
                            systemImage: "leaf.fill",
                            color: .mint
                        )
                        AchievementRow(
                            title: "Circles closed",
                            value: dayCount(summary.closedCircleDays),
                            systemImage: "checkmark.circle.fill",
                            color: .blue
                        )
                        AchievementRow(
                            title: "Days tracked",
                            value: dayCount(summary.trackedDays),
                            systemImage: "calendar",
                            color: .orange
                        )
                    }

                    Section {
                        ForEach(DrinkKind.allCases) { kind in
                            LabeledContent {
                                Text(summary.averageDailyCount(for: kind), format: .number.precision(.fractionLength(1)))
                                    .monospacedDigit()
                                Text("per day")
                                    .foregroundStyle(.secondary)
                            } label: {
                                Label(kind.title, systemImage: kind.symbol)
                                    .foregroundStyle(kind.color)
                            }
                        }
                    } header: {
                        Text("Daily Drink Averages")
                    } footer: {
                        Text("Averages include every day since you began tracking, including days without an entry.")
                    }
                }
            }
        }
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formattedVolume(_ milliliters: Double) -> String {
        let value = milliliters / unit.mlPerUnit
        if unit == .ounces {
            return "\(Int(value.rounded())) \(unit.label)"
        }
        return value.formatted(.number.precision(.fractionLength(1))) + " " + unit.label
    }

    private func dayCount(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }
}

private struct AchievementRow: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        LabeledContent {
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        } label: {
            Label(title, systemImage: systemImage)
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AchievementSummary {
    let mostWaterML: Double
    let longestCircleStreak: Int
    let longestTrackingStreak: Int
    let caffeineFreeCircleDays: Int
    let closedCircleDays: Int
    let trackedDays: Int

    private let averageCounts: [DrinkKind: Double]

    init(events: [DrinkEvent], baseGoalML: Double, calendar: Calendar = .current) {
        let eventsByDay = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.date)
        }
        let days = eventsByDay.map { date, events in
            AchievementDay(date: date, events: events, baseGoalML: baseGoalML)
        }
        .sorted { $0.date < $1.date }

        mostWaterML = days.map(\.waterML).max() ?? 0
        let closedDates = days.filter(\.closedCircle).map(\.date)
        longestCircleStreak = Self.longestStreak(in: closedDates, calendar: calendar)
        longestTrackingStreak = Self.longestStreak(in: days.map(\.date), calendar: calendar)
        caffeineFreeCircleDays = days.count { $0.closedCircle && !$0.hadCaffeine }
        closedCircleDays = closedDates.count
        trackedDays = days.count

        let elapsedDays: Int
        if let firstDate = days.first?.date {
            let today = calendar.startOfDay(for: .now)
            elapsedDays = max((calendar.dateComponents([.day], from: firstDate, to: today).day ?? 0) + 1, 1)
        } else {
            elapsedDays = 1
        }
        averageCounts = Dictionary(
            uniqueKeysWithValues: DrinkKind.allCases.map { kind in
                let count = events.lazy.filter { $0.kind == kind }.count
                return (kind, Double(count) / Double(elapsedDays))
            }
        )
    }

    func averageDailyCount(for kind: DrinkKind) -> Double {
        averageCounts[kind, default: 0]
    }

    private static func longestStreak(in dates: [Date], calendar: Calendar) -> Int {
        let sortedDates = Array(Set(dates.map { calendar.startOfDay(for: $0) })).sorted()
        guard !sortedDates.isEmpty else { return 0 }

        var longest = 1
        var current = 1
        for index in sortedDates.indices.dropFirst() {
            let previous = sortedDates[sortedDates.index(before: index)]
            if calendar.dateComponents([.day], from: previous, to: sortedDates[index]).day == 1 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }
}

private struct AchievementDay {
    let date: Date
    let waterML: Double
    let closedCircle: Bool
    let hadCaffeine: Bool

    init(date: Date, events: [DrinkEvent], baseGoalML: Double) {
        self.date = date
        waterML = events.lazy
            .filter { $0.kind == .water }
            .reduce(0) { $0 + $1.volumeML }

        let sportsDrinkML = events.lazy
            .filter { $0.kind == .sportsDrink }
            .reduce(0) { $0 + $1.volumeML }
        let caffeineCount = events.count { $0.kind == .coffee || $0.kind == .soda }
        let alcoholCount = events.count { $0.kind == .alcohol }
        let adjustmentOunces = (caffeineCount / 2) * 8 + alcoholCount * 8
        let adjustedGoalML = baseGoalML
            + Double(adjustmentOunces) * MeasurementConstants.millilitersPerOunce

        closedCircle = waterML + sportsDrinkML * 0.5 >= adjustedGoalML
        hadCaffeine = caffeineCount > 0
    }
}
