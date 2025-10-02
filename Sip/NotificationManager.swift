//
//  NotificationManager.swift
//  Sip
//
//  Created by Kevin Prigge on 10/1/25.
//

import UserNotifications
import Foundation
import Combine

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private override init() { super.init() }

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
    }

    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch { return false }
    }

    /// Clear all pending reminders (doesn't clear delivered notifications)
    func clearScheduled() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// Schedule reminders at fixed times (e.g., 9a, 11a, 1p, 3p, 5p, 7p)
    func scheduleDaily(times: [DateComponents], title: String = "Sip", body: String = "Time to drink some water 💧") {
        let center = UNUserNotificationCenter.current()
        for (idx, dc) in times.enumerated() {
            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let id = "sip.daily.\(idx)"
            let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            center.add(req)
        }
    }

    // MARK: UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

