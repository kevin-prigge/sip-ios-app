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
        NotificationManager.shared.configure()
    }
    var body: some Scene {
        WindowGroup { ContentView() }
        AssistiveAccess {
            AssistiveAccessContentView()
        }
    }
}
