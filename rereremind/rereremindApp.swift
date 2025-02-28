//
//  rereremindApp.swift
//  rereremind
//
//  Created by riko on 2025/02/24.
//

import SwiftUI
import UserNotifications


@main
struct rereremindApp: App {
    init() {
        requestNotificationPermission()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("通知の許可リクエスト失敗: \(error.localizedDescription)")
            }
        }
        
        // 通知の延長アクションを登録
        let snoozeAction = UNNotificationAction(identifier: "SNOOZE_ACTION", title: "通知を延長", options: [.foreground])
        let category = UNNotificationCategory(identifier: "REMINDER_CATEGORY", actions: [snoozeAction], intentIdentifiers: [], options: [])
        
        center.setNotificationCategories([category])
        center.delegate = NotificationHandler.shared
    }

}
