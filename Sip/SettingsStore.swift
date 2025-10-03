//
//  SettingsStore.swift
//  Sip
//
//  Created by Kevin Prigge on 10/1/25.
//
//

import Foundation
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    enum VolumeUnit: String, CaseIterable, Identifiable, Codable {
        case ounces
        case liters
        case cups
        var id: String { rawValue }
        var label: String {
            switch self {
            case .ounces: return "oz"
            case .liters: return "L"
            case .cups: return "cups"
            }
        }
        /// Number of milliliters per unit
        var mlPerUnit: Double {
            switch self {
            case .ounces: return 29.574
            case .liters: return 1000.0
            case .cups: return 236.588
            }
        }
    }

    @Published var goalML: Double { didSet { UserDefaults.standard.set(goalML, forKey: "goalML") } }
    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "notifEnabled") } }
    @Published var reminderTimesMinutes: [Int] { didSet { UserDefaults.standard.set(reminderTimesMinutes, forKey: "reminderTimesMinutes") } }
    @Published var reminderEnabled: [Bool] { didSet { UserDefaults.standard.set(reminderEnabled, forKey: "reminderEnabled") } }
    @Published var volumeUnit: VolumeUnit { didSet { UserDefaults.standard.set(volumeUnit.rawValue, forKey: "volumeUnit") } }

    init() {
        let savedGoal = UserDefaults.standard.double(forKey: "goalML")
        self.goalML = (savedGoal == 0 ? 2500 : savedGoal)
        self.enabled = UserDefaults.standard.object(forKey: "notifEnabled") as? Bool ?? true

        let savedTimes = UserDefaults.standard.array(forKey: "reminderTimesMinutes") as? [Int]
        let savedEnabled = UserDefaults.standard.array(forKey: "reminderEnabled") as? [Bool]
        let defaults = [9,11,13,15,17,19].map { $0 * 60 }
        self.reminderTimesMinutes = (savedTimes?.count == 6 ? savedTimes! : defaults)
        self.reminderEnabled = (savedEnabled?.count == 6 ? savedEnabled! : Array(repeating: true, count: 6))

        let savedUnitRaw = UserDefaults.standard.string(forKey: "volumeUnit")
        let migratedUnitRaw = (savedUnitRaw == "milliliters") ? "liters" : savedUnitRaw
        self.volumeUnit = VolumeUnit(rawValue: migratedUnitRaw ?? "") ?? .ounces
    }

    var defaultReminderTimes: [DateComponents] {
        // 9:00, 11:00, 13:00, 15:00, 17:00, 19:00 local
        [9,11,13,15,17,19].map { hour in
            var dc = DateComponents()
            dc.hour = hour; dc.minute = 0
            return dc
        }
    }

    var currentReminderTimes: [DateComponents] {
        reminderTimesMinutes.prefix(6).map { minutes in
            var dc = DateComponents()
            dc.hour = minutes / 60
            dc.minute = minutes % 60
            return dc
        }
    }
}
