//
//  SipApp.swift
//  Sip
//
//  Created by Kevin Prigge on 10/1/25.
//

import SwiftUI
import UserNotifications

@main
struct SipApp: App {
    init() {
        // Ensure the notification center delegate is set early
        UNUserNotificationCenter.current().delegate = AppNotificationManager.shared
        // Register categories (quick add actions) before any notifications are scheduled
        AppNotificationManager.shared.setupCategories()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // Request notification permission early so actions can appear
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                }
        }
        AssistiveAccess {
            AssistiveAccessContentView()
        }
    }
}
