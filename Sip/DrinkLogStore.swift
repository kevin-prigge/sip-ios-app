import Foundation
import Observation

struct DrinkEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let kind: DrinkKind
    let volumeML: Double
    let date: Date

    init(
        id: UUID = UUID(),
        kind: DrinkKind,
        volumeML: Double,
        date: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.volumeML = volumeML
        self.date = date
    }
}

struct DailyDrinkTotal: Identifiable, Equatable {
    let date: Date
    let kind: DrinkKind
    let volume: Double

    var id: String {
        "\(kind.rawValue)-\(date.timeIntervalSinceReferenceDate)"
    }
}

@MainActor
@Observable
final class DrinkLogStore {
    private(set) var events: [DrinkEvent]

    private let defaults: UserDefaults
    private let storageKey = "sip.drinkEvents"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        guard
            let data = defaults.data(forKey: storageKey),
            let savedEvents = try? JSONDecoder().decode([DrinkEvent].self, from: data)
        else {
            events = []
            return
        }

        events = savedEvents
    }

    func add(kind: DrinkKind, volumeML: Double, date: Date = .now) {
        events.append(DrinkEvent(kind: kind, volumeML: volumeML, date: date))
        save()
    }

    func dailyTotals(
        days: Int,
        kinds: Set<DrinkKind>,
        unit: SettingsStore.VolumeUnit,
        endingAt endDate: Date = .now
    ) -> [DailyDrinkTotal] {
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: endDate)
        guard let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) else {
            return []
        }

        let totalsByDayAndKind = Dictionary(grouping: events) { event in
            DayAndKind(
                date: calendar.startOfDay(for: event.date),
                kind: event.kind
            )
        }
        .mapValues { dailyEvents in
            dailyEvents.reduce(0) { $0 + $1.volumeML }
        }

        return kinds.flatMap { kind in
            (0..<days).compactMap { offset in
                guard let date = calendar.date(byAdding: .day, value: offset, to: startDay) else {
                    return nil
                }
                let milliliters = totalsByDayAndKind[DayAndKind(date: date, kind: kind), default: 0]
                return DailyDrinkTotal(
                    date: date,
                    kind: kind,
                    volume: milliliters / unit.mlPerUnit
                )
            }
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

private struct DayAndKind: Hashable {
    let date: Date
    let kind: DrinkKind
}
