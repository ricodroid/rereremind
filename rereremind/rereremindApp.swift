//
//  rereremindApp.swift
//  rereremind
//
//  Created by riko on 2025/02/24.
//

import SwiftUI
import UserNotifications


@main
struct ChatApp: App {
    init() {
        requestNotificationPermission()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("通知の許可リクエスト失敗: \(error.localizedDescription)")
            }
        }
    }
}
