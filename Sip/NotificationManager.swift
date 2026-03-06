//
//  NotificationManager.swift
//  Sip
//
//  Created by Kevin Prigge on 10/1/25.
//

import UserNotifications
import Foundation
import Combine

private enum HydrationNotificationIDs {
    static let category = "HYDRATION_REMINDER"
    static let actionAdd16 = "HYDRATION_ADD_16"
    static let actionAdd8 = "HYDRATION_ADD_8"
    static let actionAdd32 = "HYDRATION_ADD_32"
}

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private override init() { super.init() }

    /// Set this from the app to perform the actual logging when the +16 oz action is tapped.
    var onQuickAdd16: (() -> Void)?

    /// Set this from the app to perform the actual logging when the +8 oz action is tapped.
    var onQuickAdd8: (() -> Void)?

    /// Set this from the app to perform the actual logging when the +32 oz action is tapped.
    var onQuickAdd32: (() -> Void)?

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let add8 = UNNotificationAction(identifier: HydrationNotificationIDs.actionAdd8,
                                        title: "+8 oz",
                                        options: [.foreground])
        let add16 = UNNotificationAction(identifier: HydrationNotificationIDs.actionAdd16,
                                         title: "+16 oz",
                                         options: [.foreground])
        let add32 = UNNotificationAction(identifier: HydrationNotificationIDs.actionAdd32,
                                         title: "+32 oz",
                                         options: [.foreground])
        let category = UNNotificationCategory(identifier: HydrationNotificationIDs.category,
                                              actions: [add8, add16, add32],
                                              intentIdentifiers: [],
                                              options: [])
        center.setNotificationCategories([category])
    }

    /// Request notification authorization. Call this before scheduling notifications.
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

    /// Build a progress subtitle like "You're at 64/100 oz"
    func progressSubtitle(totalOunces: Int, goalOunces: Int) -> String {
        "You're at \(totalOunces)/\(goalOunces) oz"
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
            content.categoryIdentifier = HydrationNotificationIDs.category
            let id = "sip.daily.\(idx)"
            let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            center.add(req)
        }
    }

    /// Schedule an immediate hydration reminder with a given progress subtitle.
    func scheduleImmediateReminder(progressSubtitle: String,
                                   title: String = "Time to hydrate!",
                                   sound: UNNotificationSound = .default) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = progressSubtitle
        content.sound = sound
        content.categoryIdentifier = HydrationNotificationIDs.category

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "sip.hydration.immediate",
                                            content: content,
                                            trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        switch response.actionIdentifier {
        case HydrationNotificationIDs.actionAdd8:
            onQuickAdd8?()
        case HydrationNotificationIDs.actionAdd16:
            onQuickAdd16?()
        case HydrationNotificationIDs.actionAdd32:
            onQuickAdd32?()
        default:
            break
        }
    }
}
