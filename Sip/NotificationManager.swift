//
//  NotificationManager.swift
//  Sip
//
//  Created by Kevin Prigge on 10/1/25.
//

import UserNotifications
import Foundation
import Combine
import UIKit

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

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
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

    /// Schedule reminders with a snapshot of the latest hydration progress.
    func scheduleDaily(
        times: [DateComponents],
        amountML: Double,
        goalML: Double,
        unit: SettingsStore.VolumeUnit,
        title: String = "Sip",
        body: String = "It's time to drink water."
    ) async {
        let center = UNUserNotificationCenter.current()
        for (idx, dc) in times.enumerated() {
            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.categoryIdentifier = HydrationNotificationIDs.category
            content.subtitle = progressSubtitle(amountML: amountML, goalML: goalML, unit: unit)
            if let attachment = progressRingAttachment(amountML: amountML, goalML: goalML) {
                content.attachments = [attachment]
            }
            let id = "sip.daily.\(idx)"
            let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            try? await center.add(req)
        }
    }

    private func progressSubtitle(
        amountML: Double,
        goalML: Double,
        unit: SettingsStore.VolumeUnit
    ) -> String {
        let amount = amountML / unit.mlPerUnit
        let goal = goalML / unit.mlPerUnit
        if unit == .ounces {
            return "\(Int(amount.rounded())) of \(Int(goal.rounded())) \(unit.label)"
        }
        return "\(amount.formatted(.number.precision(.fractionLength(1)))) of "
            + "\(goal.formatted(.number.precision(.fractionLength(1)))) \(unit.label)"
    }

    private func progressRingAttachment(amountML: Double, goalML: Double) -> UNNotificationAttachment? {
        let progress = goalML > 0 ? min(max(amountML / goalML, 0), 1) : 0
        let size = CGSize(width: 320, height: 320)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false

        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius: CGFloat = 112
            let lineWidth: CGFloat = 28
            let startAngle = -CGFloat.pi / 2

            context.cgContext.setLineWidth(lineWidth)
            context.cgContext.setLineCap(.round)
            context.cgContext.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.16).cgColor)
            context.cgContext.addArc(
                center: center,
                radius: radius,
                startAngle: 0,
                endAngle: CGFloat.pi * 2,
                clockwise: false
            )
            context.cgContext.strokePath()

            context.cgContext.setStrokeColor(UIColor.systemCyan.cgColor)
            context.cgContext.addArc(
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: startAngle + CGFloat.pi * 2 * progress,
                clockwise: false
            )
            context.cgContext.strokePath()

            let percent = NumberFormatter.localizedString(
                from: NSNumber(value: progress),
                number: .percent
            )
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 54, weight: .bold),
                .foregroundColor: UIColor.label
            ]
            let text = NSAttributedString(string: percent, attributes: attributes)
            let textSize = text.size()
            text.draw(at: CGPoint(
                x: center.x - textSize.width / 2,
                y: center.y - textSize.height / 2
            ))
        }

        guard let data = image.pngData() else { return nil }
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sip-progress-\(UUID().uuidString)")
            .appendingPathExtension("png")
        do {
            try data.write(to: fileURL, options: .atomic)
            return try UNNotificationAttachment(identifier: "hydration-progress", url: fileURL)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
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
